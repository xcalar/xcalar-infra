#!/usr/bin/env python3

# Copyright 2019-2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import logging
import os
import sys
import threading
import time
import uuid

from pymongo import MongoClient, WriteConcern, ReturnDocument
from pymongo.errors import ConnectionFailure
from pymongo.errors import DuplicateKeyError


if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.mongodb_proxy import MongoProxy

# Defaults
mongo_db_user = 'root'
mongo_db_pass = 'Welcome1'
mongo_db_host = 'mongodb.service.consul'
mongo_db_port = '27017'

class MongoDB(object):

    ENV_CONFIG = {'MONGO_DB_HOST': {'required': True,
                                    'default': mongo_db_host},
                  'MONGO_DB_PORT': {'required': True,
                                    'type': EnvConfiguration.NUMBER,
                                    'default': mongo_db_port},
                  'MONGO_DB_USER': {'required': True,
                                    'default': mongo_db_user},
                  'MONGO_DB_PASS': {'required': True,
                                    'default': mongo_db_pass},
                  'MONGO_DB_USE_PROXY': {'default': False}}

    def __init__(self, *, db_name):
        self.logger = logging.getLogger(__name__)
        self.cfg = EnvConfiguration(MongoDB.ENV_CONFIG)
        self.url = "mongodb://{}:{}@{}:{}/"\
                   .format(self.cfg.get('MONGO_DB_USER'),
                           self.cfg.get('MONGO_DB_PASS'),
                           self.cfg.get('MONGO_DB_HOST'),
                           self.cfg.get('MONGO_DB_PORT'))
        self.client = MongoClient(self.url, connect=False)
        if self.cfg.get('MONGO_DB_USE_PROXY'):
            self.client = MongoProxy(self.client)
        # Quick connectivity check...
        # The ismaster command is cheap and does not require auth.
        self.client.admin.command('ismaster')
        self.db = self.client[db_name]
        self.logger.info(self.db)

    def collection(self, name):
        return self.db[name]

    def collection_names(self):
        return self.db.collection_names()

    def job_meta_collection_names(self):
        names = []
        for name in self.db.collection_names():
            if name.startswith('job_') and name.endswith('_meta'):
                names.append(name)
        return names

    @staticmethod
    def encode_key(key):
        return key.replace('.', '__dot__')

    @staticmethod
    def decode_key(key):
        return key.replace('__dot__', '.')


class MongoDBKALockDoubleLock(Exception):
    pass

class MongoDBKALockTimeout(Exception):
    pass

class MongoDBKALockUpdateFail(Exception):
    pass

class MongoDBKALockUnlockFail(Exception):
    pass

class MongoDBKeepAliveLock(object):

    ENV_CONFIG = {'MONGO_DB_KALOCK_COLLECTION_NAME':
                        {'required': True,
                         'default': '_ka_locks'},
                  'MONGO_DB_KALOCK_TIMEOUT':
                        {'required': True,
                         'type': EnvConfiguration.NUMBER,
                         'default': 10},
                  'MONGO_DB_KALOCK_UPDATE_FREQUENCY':
                        {'required': True,
                         'type': EnvConfiguration.NUMBER,
                         'default': 5},
                 }

    def __init__(self, *, db, name):
        self.logger = logging.getLogger(__name__)
        self.cfg = EnvConfiguration(
                        MongoDBKeepAliveLock.ENV_CONFIG)
        self.id = str(uuid.uuid4()) # Unique instance identifier
        self.db = db
        self.name = name
        self.collection = self.db.collection(
                            self.cfg.get('MONGO_DB_KALOCK_COLLECTION_NAME'))
        self.timeout = self.cfg.get('MONGO_DB_KALOCK_TIMEOUT')
        self.freq = self.cfg.get('MONGO_DB_KALOCK_UPDATE_FREQUENCY')
        self.locked = False
        self.ka_event = threading.Event()
        self.ka_thread = None

    def _ka_loop(self):
        self.logger.debug("start")
        first = True
        while self.locked:
            self.logger.debug("wait on ka_event")
            if first or not self.ka_event.wait(self.freq):
                first = False
                doc = self.collection.find_one_and_update(
                                {'_id': self.name, 'locker_id': self.id},
                                {'$set': {'timeout': int(time.time())+self.timeout}})
                if not doc:
                    self.locked = False
                    err = "failed to update _id: {} locker_id: {}"\
                          .format(self.name, self.id)
                    self.logger.error(err)
                    raise MongoDBKALockUpdateFail(err)

                if not self.locked:
                    break
        self.logger.info("stop")

    def _stop_ka(self):
        self.logger.info("start")
        if not self.ka_thread:
            self.logger.error("stopping keep alive thread without starting")
            return
        self.ka_event.set()
        self.ka_thread.join(timeout=10) # XXXrs arbitrary timeout
        if self.ka_thread.is_alive():
            self.logger.error("timeout joining keep alive thread")
        self.ka_thread = None
        self.logger.info("end")

    def _start_ka(self):
        self.logger.info("start")
        if self.ka_thread:
            self.logger.error("keep alive thread already running")
            return
        self.ka_thread = threading.Thread(target=self._ka_loop)
        self.ka_thread.daemon = True
        self.ka_thread.start()
        self.logger.info("end")

    def _try_lock(self, *, meta=None):
        """
        Try to obtain the keep-alive lock.
        """
        self.logger.debug("start")

        now = int(time.time())
        ourlock = {'_id': self.name,
                   'locker_id': self.id,
                   'timeout': now+self.timeout,
                   'meta': meta}

        # Try to create lock in the locks collection.
        try:
            self.collection.insert(ourlock)
            self.locked = True

        except DuplicateKeyError as e:
            self.logger.debug("check old")
            # Replace if not us and too old
            doc = self.collection.find_one_and_replace(
                        {'_id': self.name,
                         'locker_id': {'$ne':  self.id},
                         'timeout': {'$lt': now}},
                        ourlock)
            self.locked = doc is not None
        self.logger.debug("locked: {}".format(self.locked))
        return self.locked

    def lock(self, *, meta=None, timeout=None):
        """
        Try to acquire the lock, waiting as needed.
        """
        if timeout is None:
            timeout = self.timeout
        until = int(time.time()) + timeout
        while(not self._try_lock()):
            self.logger.debug("lock sleep...")
            time.sleep(1)
            if int(time.time()) >= until:
                err = "timeout: {} _id: {} locker_id: {}"\
                      .format(self.timeout, self.name, self.id)
                self.logger.error(err)
                raise MongoDBKALockTimeout(err)
        self._start_ka()
        return True

    def unlock(self):
        """
        Release the lock and stop the keep-alive thread.
        """
        self.locked = False
        self._stop_ka()
        result = self.collection.delete_one({'_id': self.name,
                                             'locker_id': self.id})
        if result.deleted_count != 1:
            err = "failed to delete _id: {} locker_id: {}"\
                  .format(self.name, self.id)
            self.logger.error(err)
            raise MongoDBKALockUnlockFail(err)


class JenkinsMongoDBMissingNameError(Exception):
    pass


class JenkinsMongoDB(object):

    ENV_CONFIG = {'JENKINS_HOST':    {'required': False},
                  'JENKINS_DB_NAME': {'required': False}}

    def __init__(self):
        cfg = EnvConfiguration(JenkinsMongoDB.ENV_CONFIG)
        # Explicitly pass a DB name to override the default based
        # on the Jenkins hostname.  Useful for test/debug.
        db_name = cfg.get('JENKINS_DB_NAME')
        if db_name is None:
            # Default DB name is the Jenkins host name
            db_name = cfg.get('JENKINS_HOST')
        if db_name is None:
            raise JenkinsMongoDBMissingNameError("no JENKINS_DB_NAME or JENKINS_HOST")

        # If we're using a host name, it's gonna have dots, so
        # replace with underscore to make a safe MongoDB name.
        self._db_name = "{}".format(db_name).replace('.', '_')
        self._db = None

    def jenkins_db(self):
        if not self._db:
            self._db = MongoDB(db_name=self._db_name)
        return self._db

    def _time_idx(self, *, time_ms):
        """
        Time-based collection names take the form:
            _bla_bla_bla_<time_index>

        Each collection spans 5000000000ms (roughly 59 days).
        The "time_index" is an integer divisible by 5000000000
        A job with start time T(ms) is placed into the collection
        with time_index int(T/5000000000)
        """
        return int(time_ms/5000000000)

    def time_collection_indices(self, *, start_time_ms, end_time_ms=None):
        """
        Return the list of time index values spanning the requested time period.
        """
        start = self._time_idx(time_ms=start_time_ms)
        if end_time_ms is None:
            return [start]
        if start_time_ms > end_time_ms:
            raise ValueError("start_time_ms after end_time_ms")
        end = self._time_idx(time_ms=end_time_ms)
        colls = []
        return [i for i in range(start,end+1)]

    def builds_by_time_collection(self, *, time_ms):
        """
        Return the collection associated with the timestamp
        """
        name = '_builds_by_time_{}'.format(self._time_idx(time_ms=time_ms))
        db = self.jenkins_db()
        return db.collection(name)

    def builds_by_time_collections(self, *, start_time_ms, end_time_ms):
        """
        Return the list of collections spanning the requested time period.

        It is the responsibility of the caller to iterate over the
        collections and merge search results.
        """
        idxs = self.time_collection_indices(start_time_ms=start_time_ms,
                                            end_time_ms=end_time_ms)
        db = self.jenkins_db()
        return [db.collection('_builds_by_time_{}'.format(i)) for i in idxs]

    def all_builds_by_time_collections(self):
        """
        Return the list of all builds_by_time collection names

        It is the responsibility of the caller to iterate over the
        collections and merge search results.
        """
        db = self.jenkins_db()
        names = []
        for name in db.collection_names():
            if name.startswith('_builds_by_time_'):
                names.append(db.collection(name))
        return names

    def downstream_jobs(self):
        """
        Return the downstream jobs collection.
        """
        db = self.jenkins_db()
        return db.collection('_downstream_jobs')

    def active_jobs(self, *, job_list=None):
        coll = self.jenkins_db().collection('_jenkins_meta')
        if job_list is not None:
            if not isinstance(job_list, list):
                raise ValueError("job_list must be a list")
            doc = coll.find_one_and_update({'_id': 'active'}, {'$set':{'job_list': job_list}},
                                           upsert=True, return_document = ReturnDocument.AFTER)
        else:
            doc = coll.find_one({'_id': 'active'})

        if not doc:
            return []
        return doc.get('job_list', [])

    def active_hosts(self, *, host_list=None):
        coll = self.jenkins_db().collection('_jenkins_meta')
        if host_list is not None:
            if not isinstance(host_list, list):
                raise ValueError("host_list must be a list")
            doc = coll.find_one_and_update({'_id': 'active'}, {'$set':{'host_list': host_list}},
                                           upsert=True, return_document = ReturnDocument.AFTER)
        else:
            doc = coll.find_one({'_id': 'active'})

        if not doc:
            return []
        return doc.get('host_list', [])


    def all_job_update_ts(self, *, ts=None):
        coll = self.jenkins_db().collection('_jenkins_meta')
        if ts is not None:
            if isinstance(ts, float):
                ts = int(ts)
            if not isinstance(ts, int):
                raise ValueError("ts must be a number")
            doc = coll.find_one_and_update({'_id': 'all_job_update'}, {'$set':{'ts': ts}},
                                           upsert=True, return_document = ReturnDocument.AFTER)
        else:
            doc = coll.find_one({'_id': 'all_job_update'})

        if not doc:
            return 0
        return doc.get('ts', 0)

    def alert_ttl(self, *, alert_group, alert_id, ttl):
        coll = self.jenkins_db().collection('_jenkins_meta')
        operator = '$set'
        expire = time.time()
        if not ttl:
            operator = '$unset'
        else:
            expire += ttl

        # Make it safe
        alert_group = alert_group.replace(':', '__colon__')
        alert_id = alert_id.replace(':', '__colon__')
        grp_id = ":".join([alert_group, alert_id])
        grp_id = MongoDB.encode_key(grp_id)
        return coll.find_one_and_update({'_id': 'alerts_ttl'}, {operator:{grp_id: int(expire)}},
                                        upsert=True, return_document = ReturnDocument.AFTER)

    def alerts_expired(self):
        coll = self.jenkins_db().collection('_jenkins_meta')
        doc = coll.find_one({'_id': 'alerts_ttl'})
        expired = []
        if not doc:
            return expired
        doc.pop('_id')
        now = int(time.time())
        for grp_id,expire in doc.items():
            if expire > now:
                continue
            grp_id = MongoDB.decode_key(grp_id)
            alert_group, alert_id = grp_id.split(':')
            alert_group = alert_group.replace('__colon__', ':')
            alert_id = alert_id.replace('__colon__', ':')
            expired.append([alert_group, alert_id])
        return expired

if __name__ == '__main__':
    print("Compile check A-OK!")

    # It's log, it's log... :)
    logging.basicConfig(
                    level=logging.DEBUG,
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)
    jmdb = JenkinsMongoDB()
    print(jmdb.all_builds_by_time_collections())

    """
    jmdb = JenkinsMongoDB()
    print("set: {}".format(jmdb.alert_ttl(alert_group="mine", alert_id="foo", ttl=1)))
    print("set: {}".format(jmdb.alert_ttl(alert_group="mine", alert_id="bar", ttl=3)))
    print("expired: {}".format(jmdb.alerts_expired(alert_group="mine")))
    print("sleep 2")
    time.sleep(2)
    print("expired: {}".format(jmdb.alerts_expired(alert_group="mine")))
    print("sleep 2")
    time.sleep(2)
    print("expired: {}".format(jmdb.alerts_expired(alert_group="mine")))
    print("clear bar: {}".format(jmdb.alert_ttl(alert_group="mine", alert_id="bar", ttl=None)))
    print("clear foo: {}".format(jmdb.alert_ttl(alert_group="mine", alert_id="foo", ttl=None)))
    print("clear foo again: {}".format(jmdb.alert_ttl(alert_group="mine", alert_id="foo", ttl=None)))
    print("all: {}".format(jmdb.alerts_expired(alert_group="mine")))
    """

    """
    mongo = MongoDB(db_name='unit_test_db')
    coll = mongo.collection(name='test-collection')
    coll.remove({'_id': '123'})
    coll.insert({'_id': '123'})
    while True:
        doc = coll.find_one_and_update({'_id': '123'}, {'$inc': {'counter': 1}}, return_document = ReturnDocument.AFTER)
        print(doc)
        time.sleep(1)
    """

    """
    kal1 = MongoDBKeepAliveLock(db=mongo, name="some-test-lock")
    kal2 = MongoDBKeepAliveLock(db=mongo, name="some-test-lock")
    print("lock 1...")
    kal1.lock()
    saw_expected = False
    before = int(time.time())
    try:
        time.sleep(5)
        print("lock 2...")
        kal2.lock()
    except MongoDBKALockTimeout as e:
        saw_expected = True
        print("Got timeout {}".format(e))
        pass
    if not saw_expected:
        raise Exception("timeout failed")
    diff = int(time.time())-before
    if diff < 15 or diff > 16:
        raise Exception("timeout bad diff: {}".format(diff))
    print("unlock 1...")
    kal1.unlock()
    print("lock 2...")
    kal2.lock()
    print("unlock 2...")
    kal2.unlock()
    print("DONE!")
    """

    """
    coll = mongo.collection(name='test-collection')
    print(coll)

    coll.remove({'_id': '123'})
    coll.insert({'_id': '123'})
    doc = coll.find_one_and_update({'_id': '123', 'meta':{'$exists': False}}, {'$inc': {'try_count': 1}}, return_document = ReturnDocument.AFTER)
    print(doc)
    doc = coll.find_one_and_update({'_id': '123', 'meta':{'$exists': False}}, {'$inc': {'try_count': 1}}, return_document = ReturnDocument.AFTER)
    print(doc)
    doc = coll.find_one_and_update({'_id': '123', 'meta':{'$exists': False}}, {'$unset': {'try_count': ''}, '$set': {'meta': {}}}, return_document = ReturnDocument.AFTER)
    print(doc)

    for foo in range(10):
        doc = coll.find_one_and_update({'_id': 'fooset'}, {'$addToSet': {'members': foo}}, upsert=True)
    for foo in range(15):
        doc = coll.find_one_and_update({'_id': 'fooset'}, {'$addToSet': {'members': foo}}, upsert=True)
    """
