#!/usr/bin/env python3
# Copyright 2019-2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

__all__=[]

from abc import ABC, abstractmethod
import logging
import os
import pymongo
from pymongo.errors import DuplicateKeyError
from pymongo import ReturnDocument
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_api import JenkinsApi
from py_common.mongo import MongoDB, JenkinsMongoDB
from py_common.prometheus_api import PrometheusAPI
from py_common.sorts import nat_sort


class JenkinsAllJobIndex(object):
    """
    Interface to the collections that keep particular meta-data
    spanning multiple jobs.
    """

    def __init__(self, *, jmdb):
        self.logger = logging.getLogger(__name__)
        self.jmdb = jmdb

    def index_data(self, *, job_name, bnum, data, is_done, is_reparse):
        """
        Expects to find at least the following in data:
            {'parameters': jbi.parameters(),
             'git_branches': jbi.git_branches(),
             'built_on': jbi.built_on(),
             'start_time_ms': jbi.start_time_ms(),
             'duration_ms': jbi.duration_ms(),
             'end_time_ms': jbi.end_time_ms(),
             'result': jbi.result()}
        """

        self.logger.debug("job_name: {} bnum: {}".format(job_name, bnum))

        start_time_ms = data.get('start_time_ms', None)
        duration_ms = data.get('duration_ms', None)

        # end time was not originally supported, so might be missing
        # manufacture it if needed
        end_time_ms = data.get('end_time_ms', None)
        if end_time_ms is None and start_time_ms is not None and duration_ms is not None:
            end_time_ms = start_time_ms + duration_ms

        built_on = data.get('built_on', None)
        result = data['result'] or "PENDING" # XXXrs humm....

        job_entry = {'job_name': job_name,
                     'build_number': bnum,
                     'start_time_ms': start_time_ms,
                     'duration_ms': duration_ms,
                     'end_time_ms': end_time_ms,
                     'built_on': built_on,
                     'result': result}

        self.logger.debug("job_entry: {}".format(job_entry))

        # Jobs by time
        if start_time_ms is not None and not is_reparse:
            coll = self.jmdb.builds_by_time_collection(time_ms=start_time_ms)
            coll.create_index([('job_name', pymongo.ASCENDING),
                               ('build_number', pymongo.ASCENDING)],
                              unique=True)
            coll.find_one_and_replace({'job_name':job_name, 'build_number': bnum},
                                       job_entry, upsert=True)

        # Downstream Jobs
        coll = self.jmdb.downstream_jobs()
        down_key = "{}:{}".format(job_name, bnum)
        for item in data.get('upstream', []):
            self.logger.debug('upstream: {}'.format(item))
            up_jname = item.get('job_name', None)
            if not up_jname:
                self.logger.error("missing expected upstream job_name: {}".format(item))
                continue
            up_bnum = item.get('build_number', None)
            if not up_bnum:
                self.logger.error("missing expected upstream build_number: {}".format(item))
                continue
            up_key = "{}:{}".format(up_jname, up_bnum)
            self.logger.debug("up_key {} down_key {}".format(up_key, down_key))
            coll.find_one_and_update({'_id': up_key},
                                     {'$addToSet': {'down': down_key}},
                                     upsert = True)

    def builds_by_time(self, *, start_time_ms, end_time_ms, full=False):
        '''
        Return all builds that started between start and end times.
        '''
        # Build start time after period start time AND
        # build start time before period end time
        query = {'$and': [{'start_time_ms': {'$gte': start_time_ms}},
                          {'start_time_ms': {'$lt': end_time_ms}}]}

        colls = self.jmdb.builds_by_time_collections(
                                    start_time_ms=start_time_ms,
                                    end_time_ms=end_time_ms)
        builds = []
        for coll in colls:
            docs = coll.find(query)
            if not docs:
                continue
            for doc in docs:
                if full:
                    doc['collection_name'] = coll.name
                else:
                    doc.pop('_id')
                builds.append(doc)
        return {'builds': builds}

    def builds_active_between(self, *, start_time_ms, end_time_ms, full=False):
        '''
        Return all builds that were active between the start and end time.
        '''
        # Build start time before period end time AND
        # build end time after period start time
        query = {'$and': [{'start_time_ms': {'$lte': end_time_ms}},
                          {'end_time_ms': {'$gte': start_time_ms}}]}

        builds = []
        for coll in self.jmdb.all_builds_by_time_collections():
            docs = coll.find(query)
            if not docs:
                continue
            for doc in docs:
                if full:
                    doc['collection_name'] = coll.name
                else:
                    doc.pop('_id')
                builds.append(doc)
        return {'builds': builds}

    def _get_downstream(self, *, job_name, bnum):
        rtn = []
        key = "{}:{}".format(job_name, bnum)
        doc = self.jmdb.downstream_jobs().find_one({'_id': key})
        if not doc:
            return None
        for downkey in doc.get('down'):
            job_name, bnum = downkey.split(':')
            rtn.append({'job_name': job_name,
                        'build_number': bnum,
                        'downstream': self._get_downstream(job_name=job_name, bnum=bnum)})
        if not len(rtn):
            return None
        return rtn

    def downstream_jobs(self, *, job_name, bnum):
        return {'downstream': self._get_downstream(job_name=job_name, bnum=bnum)}


class JenkinsJobDataCollection(object):
    """
    Interface to the per-job job data collection.
    """
    def __init__(self, *, job_name, jmdb):
        self.db = jmdb.jenkins_db()
        self.logger = logging.getLogger(__name__)
        self.job_name = job_name
        self.coll = self.db.collection("job_{}".format(job_name))

    def _no_data(self, *, doc):
        return not doc or 'NODATA' in doc

    def store_data(self, *, bnum, data, is_done, is_reparse):
        """
        Store the passed data, or no-data marker if data is None
        """
        if data is None:
            try:
                self.coll.insert({'_id': bnum, 'NODATA':True})
            except DuplicateKeyError as e:
                doc = self.coll.find_one({'_id': bnum})
                if doc and not self._no_data(doc=doc):
                    # Either we're "fixing" old issues with failing to store
                    # NODATA entries in the meta index all_builds, or we're
                    # potentially overwriting "real" data with NODATA.
                    # In either case, just don't.
                    self.logger.error("attempting to overwrite with NODATA at {}:{}"
                                      .format(self.job_name, bnum))
            return

        data['_id'] = bnum
        self.coll.find_one_and_replace({'_id':bnum}, data, upsert=True)
        data.pop('_id')

    def get_data(self, *, bnum):
        self.logger.debug("start bnum {}".format(bnum))
        # Return the data, if any.
        doc = self.coll.find_one({'_id': bnum})
        if self._no_data(doc=doc):
            self.logger.debug("return None")
            return None
        self.logger.debug("return match")
        return doc

    def get_data_by_build(self):
        self.logger.debug("start")
        rtn = {}
        for doc in self.coll.find({}):
            doc_id = doc["_id"]
            self.logger.debug("_id: {}".format(doc_id))
            if self._no_data(doc=doc):
                continue
            rtn[doc_id] = doc
        self.logger.debug("rtn: {}".format(rtn))
        return rtn


class JenkinsHostDataCollection(object):
    """
    Interface to the per-host data collection.
    """
    def __init__(self, *, host_name, jmdb):
        self.db = jmdb.jenkins_db()
        self.logger = logging.getLogger(__name__)
        self.host_name = host_name
        self.coll = self.db.collection("host_{}".format(host_name))
        self.coll.create_index([('job_name', pymongo.ASCENDING),
                               ('build_number', pymongo.ASCENDING)],
                               unique=True)

    def _no_data(self, *, doc):
        return not doc or 'NODATA' in doc

    def store_data(self, *, job_name, bnum, data, is_done, is_reparse):
        """
        Store the data. :)

        N.B. is_done is here for consistency, but not presently used.
        """
        if not data or is_reparse:
            return

        # end time was not originally supported, so might be missing
        # manufacture it if needed
        start_time_ms = data.get('start_time_ms', None)
        duration_ms = data.get('duration_ms', None)
        end_time_ms = data.get('end_time_ms', None)
        if end_time_ms is None and start_time_ms is not None and duration_ms is not None:
            end_time_ms = start_time_ms + duration_ms

        result = data['result'] or "PENDING" # XXXrs humm....

        # Only selected data items.
        data = {'job_name': job_name,
                'build_number': bnum,
                'start_time_ms': start_time_ms,
                'duration_ms': duration_ms,
                'end_time_ms': end_time_ms,
                'result': result}

        self.coll.find_one_and_replace({'job_name':job_name, 'build_number': bnum},
                                       data, upsert=True)

class JenkinsJobMetaCollection(object):
    """
    Interface to the per-job meta-data collection.
    """
    ENV_PARAMS = {'JENKINS_AGGREGATOR_UPDATE_RETRY_MAX':
                    {'required': True,
                     'type': EnvConfiguration.NUMBER,
                     'default': 3}}

    def __init__(self, *, job_name, jmdb):
        self.db = jmdb.jenkins_db()
        self.logger = logging.getLogger(__name__)
        self.job_name = job_name
        self.coll = self.db.collection("job_{}_meta".format(job_name))
        cfg = EnvConfiguration(JenkinsJobMetaCollection.ENV_PARAMS)
        self.retry_max = cfg.get('JENKINS_AGGREGATOR_UPDATE_RETRY_MAX')

    def index_data(self, *, bnum, data, is_done, is_reparse):
        """
        Extract certain meta-data from the data set and "index".
        This is largly for the purpose of dashboard time efficiency.
        This may become obsolete when data are processed/indexed via
        Xcalar.

        is_reparse is here for consistency with other similar
        index/store methods, but is not presently used.
        """
        if is_done:
            self.logger.info("processing completed build {}:{}"
                             .format(self.job_name, bnum))
            # Add to all_builds list when complete
            self.coll.find_one_and_update({'_id': 'all_builds'},
                                          {'$addToSet': {'builds': bnum}},
                                          upsert = True)

        else:
            self.logger.info("processing incomplete build {}:{}"
                             .format(self.job_name, bnum))

        # Remove any retry entry
        self.cancel_retry(bnum=bnum)

        # Remove any reparse entry
        self.cancel_reparse(bnum=bnum)

        if not data:
            self.logger.error("empty data for {}:{}"
                             .format(self.job_name, bnum))
            return # Nothing more to do.

        # If we have branch data, add to the builds-by-branch list(s)
        git_branches = data.get('git_branches', {})
        for repo, branch in git_branches.items():

            # Add repo to all repos list
            self.coll.find_one_and_update({'_id': 'all_repos'},
                                          {'$addToSet': {'repos': repo}},
                                          upsert = True)

            # Add branch to list of branches for the repo
            key = MongoDB.encode_key("{}_branches".format(repo))
            self.coll.find_one_and_update({'_id': key},
                                          {'$addToSet': {'branches': branch}},
                                          upsert = True)

            # Add build to the list of builds for the repo/branch pair
            key = MongoDB.encode_key("{}_{}_builds".format(repo, branch))
            self.coll.find_one_and_update({'_id': key},
                                          {'$addToSet': {'builds': bnum}},
                                           upsert = True)

        # _add_to_meta_set is a list of key/val pairs.  The key will define a document,
        # and the val will be added to the 'values' set in that document iff it is not
        # already present.
        add_to_meta_set = data.pop('_add_to_meta_set', [])
        for key,val in add_to_meta_set:
            self.coll.find_one_and_update({'_id': key},
                                          {'$addToSet': {'values': val}},
                                          upsert = True)

    def store_data(self, *, key, data):
        """
        Store the passed data, or delete any existing if data is None
        """
        if data is None:
            self.coll.find_one_and_delete({'_id': key})
            return
        data['_id'] = key
        self.coll.find_one_and_replace({'_id': key}, data, upsert=True)
        data.pop('_id')

    def get_data(self, *, key):
        doc = self.coll.find_one({'_id': key})
        if not doc:
            return {}
        doc.pop('_id', None)
        return doc

    def all_builds(self):
        """
        Return the list of all builds for which we have final data.
        Note that this does not include incomplete or "PENDING" builds.
        We may have data indexed for such builds, but don't list them
        here so we will continue to monitor status until they return a
        final result.
        """
        doc = self.coll.find_one({'_id': 'all_builds'})
        if not doc:
            return []
        return sorted(doc.get('builds', []))

    def pending_builds(self, *, first, last):
        """
        Return list of pending (no recorded result) build numbers between
        first and last (inclusive)
        """
        build_range = set([str(i) for i in range(first, last+1)])
        completed_builds = set(self.all_builds())
        return sorted([str(i) for i in (build_range-completed_builds)],
                      key=nat_sort, reverse=True)

    def schedule_retry(self, *, bnum):
        """
        If an attempt to obtain update data encounters a temporary
        failure schedule_retry() is called.

        If schedule_retry() has not been called on the build previously,
        the build will be added to the retry set, and its retry counter
        will be set to 1. If the build is already in the set, its retry
        counter is incremented.

        If the retry counter exceeds the maximum threshold, the build is 
        removed from the retry set and schedule_retry() returns FALSE and
        the caller is expected to insert a NO DATA marker into the DB
        for the build to suppress further update attempts.

        Otherwise, schedule_retry() returns TRUE and the caller moves on.
        """
        bnum = str(bnum)
        doc = self.coll.find_one_and_update(
                        {'_id': 'retry'},
                        {'$inc': {'{}.count'.format(bnum): 1}},
                        upsert = True,
                        return_document = ReturnDocument.AFTER)
        item = doc[bnum]
        if item['count'] > self.retry_max:
            # Out of retries.  Caller should mark build as NO DATA
            # to stop further update attempts.
            self.coll.find_one_and_update(
                        {'_id': 'retry'}, {'$unset': {bnum:""}})
            return False
        # Another retry is allowed.  The caller can skip the build
        # and allow the next update pass to make another attempt.
        return True

    def cancel_retry(self, *, bnum):
        """
        Remove the build from the retry set.
        """
        self.coll.find_one_and_update(
                    {'_id': 'retry'}, {'$unset': {str(bnum):""}})

    def reparse(self, *, builds=None, rtnmax=1):
        """
        If builds are given, add them to the "reparse" set and initialize
        the reparse counter.

        If no builds are given, scan the set, deleting any entries with
        counter exceeding the maximum, and returning any others (up to
        the maximum requested) while incrementing their counters.
        """
        if builds is None:
            rtn = []
            doc = self.coll.find_one({'_id': 'reparse'})
            if not doc:
                return(rtn)
            doc.pop('_id')
            cnt = 0
            for bnum,item in doc.items():
                if item['count'] > self.retry_max:
                    self.coll.find_one_and_update(
                        {'_id': 'reparse'}, {'$unset': {bnum:""}})
                    continue

                self.coll.find_one_and_update(
                        {'_id': 'reparse'},
                        {'$inc': {'{}.count'.format(bnum): 1}})
                rtn.append(bnum)
                if len(rtn) == rtnmax:
                    break
            return(sorted(rtn))

        all_builds = self.all_builds()
        for bnum in builds:
            if bnum not in all_builds:
                # We haven't parsed in the first place.
                # No reparse needed.
                continue
            self.coll.find_one_and_update(
                        {'_id': 'reparse'},
                        {'$set': {'{}.count'.format(bnum): 1}},
                        upsert = True,
                        return_document = ReturnDocument.AFTER)
        return

    def cancel_reparse(self, *, bnum):
        """
        Remove the build from the reparse set.
        """
        self.coll.find_one_and_update(
                        {'_id': 'reparse'}, {'$unset': {str(bnum): ""}})

    def repos(self):
        # Return all known repos
        doc = self.coll.find_one({'_id': 'all_repos'})
        if not doc:
            return []
        return list(doc.get('repos', []))

    def branches(self, *, repo):
        # Return all known branches for the repo
        key = MongoDB.encode_key('{}_branches'.format(repo))
        doc = self.coll.find_one({'_id': key})
        if not doc:
            return []
        return list(doc.get('branches', []))

    def find_builds(self, *, repo=None,
                             branches=None,
                             first_bnum=None,
                             last_bnum=None,
                             reverse=False):
        """
        Return list (possibly empty) of build numbers matching the
        given attributes.
        """

        if branches and not repo:
            raise ValueError("branches requires repo")
        # n.b. repo without branches is a no-op

        all_builds = self.all_builds()
        if not all_builds:
            return []
        all_builds = sorted(all_builds, key=nat_sort)
        if first_bnum or last_bnum and not (first_bnum and last_bnum):
            if not first_bnum:
                first_bnum = all_builds[0]
            if not last_bnum:
                last_bnum = all_builds[-1]

        build_range = None
        if first_bnum:
            build_range = set([str(b) for b in  range(int(first_bnum), int(last_bnum)+1)])

        avail_builds = set()
        if repo:
            # Just those matching repo/branch
            for branch in branches:
                key = MongoDB.encode_key("{}_{}_builds".format(repo, branch))
                doc = self.coll.find_one({'_id': key})
                if not doc:
                    continue
                avail_builds.update(doc.get('builds', []))
        else:
            avail_builds.update(all_builds)

        # If our build range is limited, intersect...
        if build_range:
            build_list = list(avail_builds.intersection(build_range))
        else:
            build_list = list(avail_builds)

        return sorted(build_list, key=nat_sort, reverse=reverse)


class JenkinsAggregatorDataUpdateTemporaryError(Exception):
    """
    Raised by subclass if update_build() encounters a failure that may be
    temporary and which may go away with a subsequent retry.
    """
    pass


class JenkinsAggregatorBase(ABC):
    """
    Base class for aggregating data and meta-data
    associated with a specific Jenkins job.
    """
    def __init__(self, *, job_name, agg_name, send_log_to_update = False):
        """
        Initializer.

        Required parameters:
            job_name:   Jenkins job name

        Optional parmaeters:
            send_log_to_update: whether or not to send the full Jenkins
                                console log to the update_build() method
                                as the value of the "log" parameter.
                                Default is False.
        """
        self.logger = logging.getLogger(__name__)
        # XXXrs - The job name is not reliable since when we configure
        #         for __ALL__ jobs, that's what shows up here.
        self.job_name = job_name
        self.agg_name = agg_name
        self.send_log_to_update = send_log_to_update

    @abstractmethod
    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Aggregate and return build-related data and meta-data.
        Every aggregator must implement the update_build() method.

        Required Parameters:
            jbi:  JenkinsBuildInfo instance (if not available will be passed as None)
            log:  the associated console log if requested via send_log_to_update
                  initializer parameter.  Will be set to None if not requested.

        Returns:
            Data structure to be associated with the build number (if any).
        """
        pass


class JenkinsJobInfoAggregator(JenkinsAggregatorBase):
    """
    Default Jenkins data aggregation.
    Returns common Jenkins-supplied build information.
    Used for all jobs.
    """
    def __init__(self, *, jenkins_host, job_name):
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__)
        self.logger = logging.getLogger(__name__)
        self.japi = JenkinsApi(host=jenkins_host)

    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):

        self.logger.debug("start job: {} bnum: {}"
                          .format(jbi.job_name, jbi.build_number))
        rtn = {}
        if jbi is None:
            self.logger.error("no build info passed, so return empty")
            return rtn

        build_host = jbi.built_on()
        try:
            # This is the "standard" set of job data.
            # Note that the JenkinsAllJobIndex class counts
            # on what's here.
            rtn = {'parameters': jbi.parameters(),
                   'git_branches': jbi.git_branches(),
                   'built_on': build_host,
                   'start_time_ms': jbi.start_time_ms(),
                   'duration_ms': jbi.duration_ms(),
                   'end_time_ms': jbi.end_time_ms(),
                   'result': jbi.result()}
            upstream = jbi.upstream()
            if upstream:
                rtn['upstream'] = upstream

        except Exception as e:
            self.logger.exception("failed to get build info")
            raise JenkinsAggregatorDataUpdateTemporaryError("try again") from None

        if build_host is not None:
            try:
                start_time_s = int(jbi.start_time_ms()/1000)
                end_time_s = int(jbi.end_time_ms()/1000)
                if end_time_s - start_time_s > 60:
                    host_metrics = PrometheusAPI().host_metrics(
                                        host = build_host,
                                        start_time_s = start_time_s,
                                        end_time_s = end_time_s)
                    rtn['host_metrics'] = host_metrics
                else:
                    self.logger.info("skipping host metrics, test duration too short")
            except Exception as e:
                self.logger.exception("failed to get host metrics")

        self.logger.debug("rtn: {}".format(rtn))
        return rtn

class JenkinsPostprocessorBase(ABC):
    """
    Base class for post-procesing data and meta-data
    associated with a specific Jenkins job.
    """
    def __init__(self, *, name, job_name):
        """
        Initializer.

        Required parameters:
            name:       any returned data will be stored in the job's
                        meta-collection using this as the document _id
            job_name:   Jenkins job name

        """
        self.logger = logging.getLogger(__name__)
        self.name = name
        # XXXrs - The job name is not reliable since when we configure
        #         for __ALL__ jobs, that's what shows up here.
        self.job_name = job_name

    @abstractmethod
    def update_job(self, *, test_mode=False):
        """
        Post-process and return any result data structure.
        Every post-processor must implement the update_job method.

        Required Parameters:
            None

        Returns:
            Data structure to be associated with the job.
            Will be stored in the job's meta-collection with
            _id equal to the value of self.name
        """
        pass


class JenkinsJobPostprocessor(JenkinsPostprocessorBase):
    """
    Default Jenkins job post-processing.
    Used for all jobs.
    """

    def __init__(self, *, jenkins_host, job_name):
        super().__init__(name="default_postprocessor", job_name=job_name)
        self.logger = logging.getLogger(__name__)
        self.japi = JenkinsApi(host=jenkins_host)
        self.jmdb = JenkinsMongoDB()
        self.alljob = JenkinsAllJobIndex(jmdb=self.jmdb)

    def _job_stats(self, *, builds):
        self.logger.info("start")
        rtn = {'build_cnt': 0, 'pass_avg_duration_s': 0, 'pass_pct': 0}
        builds = builds.get('builds', None)
        if not builds:
            return rtn
        build_cnt = 0
        pass_cnt = 0
        fail_cnt = 0
        pass_total_duration_ms = 0
        for bld in builds:
            job_name = bld.get('job_name', None)
            if not job_name or job_name != self.job_name:
                continue
            build_cnt += 1
            result = bld.get('result', None)
            if not result or result == 'ABORTED':
                continue
            elif result == 'FAILURE':
                fail_cnt += 1
                continue
            elif result != 'SUCCESS':
                continue
            pass_cnt += 1
            pass_total_duration_ms += bld.get('duration_ms', 0)
        rtn['build_cnt'] = build_cnt
        if not pass_cnt:
            return rtn
        rtn['pass_avg_duration_s'] = int((pass_total_duration_ms/pass_cnt)/1000)
        rtn['pass_pct'] = (pass_cnt/(pass_cnt+fail_cnt))*100
        return rtn

    def update_job(self, *, test_mode=False):
        """
        N.B. test_mode is ignored
        """
        self.logger.info("start job_name: {}".format(self.job_name))
        bch = {} # build count history
        pph = {} # pass percentage history
        pdh = {} # pass duration history
        try:
            day_ms = 3600000 * 24
            now = int(time.time()*1000)
            periods = [{'label': 'last_24h', 'start': now-day_ms, 'end': now},
                       {'label': 'prev_24h', 'start': now-(day_ms*2), 'end': now-day_ms-1},
                       {'label': 'last_7d', 'start': now-(day_ms*7), 'end':now},
                       {'label': 'prev_7d', 'start': now-(day_ms*14), 'end': now-(day_ms*7)-1},
                       {'label': 'last_30d', 'start': now-(day_ms*30), 'end': now},
                       {'label': 'prev_30d', 'start': now-(day_ms*60), 'end': now-(day_ms*30)-1}]
            for period in periods:
                builds = self.alljob.builds_by_time(start_time_ms = period['start'],
                                                    end_time_ms = period['end'])
                stats = self._job_stats(builds=builds)
                bch[period['label']] = stats['build_cnt']
                pph[period['label']] = stats['pass_pct']
                pdh[period['label']] = stats['pass_avg_duration_s']

                # XXXrs - consider alerting

        except Exception as e:
            self.logger.exception("update_job exception")
            return None

        rtn = {'build_cnt':bch,
               'pass_pct':pph,
               'pass_avg_duration_s':pdh}
        self.logger.info("rtn: {}".format(rtn))
        return rtn


from importlib import import_module

class Plugins(object):

    def __init__(self, *, pi_label):
        self.logger = logging.getLogger(__name__)
        plugins_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                                   "update", "plugins")
        self.byjob = {}
        for name in os.listdir(plugins_dir):
            if not name.endswith('.py'):
                continue
            mname = name[:-3]
            mpath = "plugins.{}".format(mname)
            try:
                mod = import_module(mpath)
            except:
                self.logger.exception("exception importing module: {}"
                                      .format(mpath))
                raise

            try:
                defs = getattr(mod, pi_label)
                self.logger.debug("loaded: {}".format(mname))
                self.logger.debug("{} defs: {}".format(pi_label, defs))
            except AttributeError as e:
                self.logger.info("{} does not contain {}".format(mname, pi_label))
                continue

            for info in defs:
                for job_name in info.get('job_names', []):
                    mpath = info.get('module_path', None)
                    if mpath:
                        try:
                            mod = import_module(mpath)
                        except:
                            self.logger.exception("exception importing module: {}"
                                                  .format(mpath))
                            raise
                    cname = info.get('class_name')
                    cls = getattr(mod, cname)(job_name=job_name)
                    self.logger.info('registering plugin {} for {}'.format(cname, job_name))
                    self.byjob.setdefault(job_name, []).append(cls)

    def by_job(self, *, job_name):
        plugins = self.byjob.get(job_name, [])
        plugins.extend(self.byjob.get('__ALL__', []))
        self.logger.info("plugins by_job {}: {}".format(job_name, plugins))
        return plugins


class AggregatorPlugins(Plugins):
    def __init__(self):
        super().__init__(pi_label="AGGREGATOR_PLUGINS")


class PostprocessorPlugins(Plugins):
    def __init__(self):
        super().__init__(pi_label="POSTPROCESSOR_PLUGINS")


# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")

    import pprint

    jmdb = JenkinsMongoDB()
    jaji = JenkinsAllJobIndex(jmdb=jmdb)
    now_ms = int(time.time()*1000)
    day_ms = 24*60*60*1000
    end_ms = now_ms-day_ms
    start_ms = end_ms-day_ms
    builds = jaji.builds_active_between(
                            start_time_ms=start_ms,
                            end_time_ms=end_ms)

    for build in builds['builds']:
        bstart_ms = build['start_time_ms']
        bend_ms = build['end_time_ms']
        if bstart_ms < start_ms and bend_ms < start_ms:
            raise Exception("EARLY: start {} end {} bstart {} bend {}"
                            .format(start_ms, end_ms, bstart_ms, bend_ms))
        if bstart_ms > end_ms and bend_ms > end_ms:
            raise Exception("LATE: start {} end {} bstart {} bend {}"
                            .format(start_ms, end_ms, bstart_ms, bend_ms))
        if bstart_ms < start_ms:
            print("Starts before!")
        if bend_ms > end_ms:
            print("Ends after!")

        print(pprint.pformat(build))

    '''
    cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO}})

    # It's log, it's log... :)
    logging.basicConfig(
                    level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    jmdb = JenkinsMongoDB()
    meta_coll = JenkinsJobMetaCollection(job_name="TestJob", jmdb=jmdb)
    print(meta_coll.schedule_retry(bnum=1))
    meta_coll.cancel_retry(bnum=1)
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))
    print(meta_coll.schedule_retry(bnum=1))


    meta_coll.reparse(builds=[1,2,3,10])
    print(meta_coll.reparse())
    meta_coll.cancel_reparse(bnum=3)
    meta_coll.reparse(builds=[4,5,6])
    print(meta_coll.reparse())
    meta_coll.reparse(builds=[4])
    meta_coll.cancel_reparse(bnum=6)
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())
    print(meta_coll.reparse())

    logger.info('jmdb: {}'.format(jmdb))
    alljob_idx = JenkinsAllJobIndex(jmdb=jmdb)
    logging.info(alljob_idx)
    logging.info(alljob_idx.downstream_jobs(job_name='DailyTests-Trunk', bnum='153'))
    '''
