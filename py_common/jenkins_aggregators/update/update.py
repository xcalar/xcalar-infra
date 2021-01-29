#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

from abc import ABC, abstractmethod
import json
import logging
import os
import pprint
from pymongo.errors import DuplicateKeyError
from pymongo import ReturnDocument
import signal
import sys
import time

sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsHostDataCollection
from py_common.jenkins_aggregators import JenkinsJobDataCollection
from py_common.jenkins_aggregators import JenkinsJobMetaCollection
from py_common.jenkins_aggregators import JenkinsAllJobIndex
from py_common.jenkins_aggregators import JenkinsJobInfoAggregator
from py_common.jenkins_aggregators import JenkinsJobPostprocessor
from py_common.jenkins_aggregators import JenkinsAggregatorDataUpdateTemporaryError
from py_common.jenkins_aggregators import AggregatorPlugins
from py_common.jenkins_aggregators import PostprocessorPlugins
from py_common.jenkins_aggregators.update.alerting import AlertManager
from py_common.jenkins_api import JenkinsApi
from py_common.mongo import JenkinsMongoDB, MongoDBKeepAliveLock, MongoDBKALockTimeout
from py_common.sorts import nat_sort


class JenkinsJobAggregators(object):
    """
    Controller class for set of aggregators for a job.
    Handles aggregator execution, storing of returned data, retries.
    """
    ENV_PARAMS = {'JENKINS_AGGREGATOR_UPDATE_BUILDS_MAX':
                    {'required': True,
                     'type': EnvConfiguration.NUMBER,
                     'default': 25},
                  'JENKINS_AGGREGATOR_UPDATE_FREQ_SEC':
                    {'required': True,
                     'type': EnvConfiguration.NUMBER,
                     'default': 300} }

    def __init__(self, *, jenkins_host, job_name, jmdb,
                          aggregator_plugins=None,
                          postprocessor_plugins=None):
        """
        Initializer.

        Required parameters:
            job_name:   Jenkins job name
            jmdb:       JenkinsMongoDB.jenkins_db() instance

        Optional parameters:
            aggregator_plugins: custom aggregator plug-in classes
            postprocessor_plugins: custom post-process plug-in classes
        """
        self.logger = logging.getLogger(__name__)
        self.jenkins_host = jenkins_host
        self.job_name = job_name
        self.aggregator_plugins = aggregator_plugins
        self.postprocessor_plugins = postprocessor_plugins

        cfg = EnvConfiguration(JenkinsJobAggregators.ENV_PARAMS)
        self.builds_max = cfg.get('JENKINS_AGGREGATOR_UPDATE_BUILDS_MAX')

        # XXXrs - This is presently unused.  Want to stash the time of
        #         last update, and refuse to run again until sufficient
        #         time has passed.
        self.freq_sec = cfg.get('JENKINS_AGGREGATOR_UPDATE_FREQ_SEC')

        self.job_data_coll = JenkinsJobDataCollection(job_name=job_name, jmdb=jmdb)
        self.job_meta_coll = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)
        self.alljob_idx = JenkinsAllJobIndex(jmdb=jmdb)
        self.japi = JenkinsApi(host=self.jenkins_host)

    def _update_build(self, *, bnum, is_reparse=False, test_mode=False, test_data_path=None):
        """
        Call all aggregators on the build.  Consolidate results
        and store to the DB.  All or nothing.  All aggregators
        must run successfully or we bail and try again in the
        future (if allowed).

        If test_mode is set it is allowed to pass a job name
        and build number unknown to Jenkins so that an aggregator
        in development can be triggered.  In this case, a
        JenkinsBuildInfo will be constructed with "faked" data.
        """
        self.logger.info("process bnum: {}".format(bnum))

        is_done = False
        try:
            jbi = self.japi.get_build_info(job_name=self.job_name, build_number=bnum)
            # Track whether or not the build is complete.
            # For incomplete builds, record basic build information but do not call
            # plug-in aggregators until the build finishes since that was the original
            # semantic.
            is_done = jbi.is_done()

        except Exception as e:
            if not test_mode:
                self.logger.exception("exception processing bnum: {}".format(bnum))
                if not is_reparse and not self.job_meta_coll.schedule_retry(bnum=bnum):
                    self.job_meta_coll.index_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                    self.job_data_coll.store_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                return False

            # TEST_MODE -----

            self.logger.info("get_build_info exception in test mode")
            self.logger.info("test_data_path: {}".format(test_data_path))

            # If the test job doesn't exist on Jenkins, we'll end up here.
            # In this case, we "fake up" a JenkinsBuildInfo using
            # data either defined in an external file (possibly keyed
            # by build number so that multiple builds can have different
            # "fake" data) or defined below as a static blob.

            fake_data = {'building': False,
                         "actions": [ {"parameters": [{"name": "XCE_GIT_BRANCH", "value": "trunk"},
                                                      {"name": "XD_GIT_BRANCH", "value": "trunk"},
                                                      {"name": "INFRA_GIT_BRANCH", "value": "master"}]}],
                         'builtOn': 'fakehost.somecompany.com',
                         'timestamp': int((time.time()*1000))-3600,
                         'duration': 600,
                         'result': 'SUCCESS'}

            test_data = None
            if test_data_path:
                with open(test_data_path) as json_file:
                    data = json.load(json_file)
                if bnum in data:
                    # keyed by build
                    test_data = data[bnum]
                else:
                    # same data no matter what build
                    test_data = data
            if not test_data:
                test_data = fake_data

            self.logger.info("test_data: {}".format(test_data))
            try:
                jbi = self.japi.get_build_info(job_name=self.job_name,
                                               build_number=bnum,
                                               test_data=test_data)
                is_done = jbi.is_done()
            except Exception as e:
                self.logger.exception("exception processing bnum: {}".format(bnum))
                if not is_reparse and not self.job_meta_coll.schedule_retry(bnum=bnum):
                    self.job_meta_coll.index_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                    self.job_data_coll.store_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                return False

        # Everybody gets the default aggregator
        aggregators = [JenkinsJobInfoAggregator(jenkins_host=self.jenkins_host, job_name=self.job_name)]

        if is_done:
            # Add any custom aggregator plugin(s) registered for the job.
            #
            # N.B.: We only run custom aggregators on completed builds to
            # preserve earlier semantics.
            if self.aggregator_plugins:
                aggregators.extend(self.aggregator_plugins)

        send_log = False
        for aggregator in aggregators:
            if aggregator.send_log_to_update:
                send_log = True
                break

        console_log = None
        if send_log:
            try:
                self.logger.info("get log")
                console_log = jbi.console()
            except Exception as e:
                self.logger.exception("exception processing bnum: {}".format(bnum))
                if not is_reparse and not self.job_meta_coll.schedule_retry(bnum=bnum):
                    self.job_meta_coll.index_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                    self.job_data_coll.store_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                return False

        merged_data = {}
        for agg in aggregators:
            try:
                params =  {'jbi': jbi,
                           'log': None,
                           'is_reparse': is_reparse,
                           'test_mode': test_mode}
                if agg.send_log_to_update:
                    params['log'] = console_log
                self.logger.info('calling aggregator: {}'.format(agg.agg_name))
                data = agg.update_build(**params) or {}

            except JenkinsAggregatorDataUpdateTemporaryError as e:
                # Subclass update_build() encountered a temporary error
                # while trying to gather build information. 
                # Bail, and try again in a bit (if we can).
                self.logger.exception("exception processing bnum: {}".format(bnum))
                if not is_reparse and not self.job_meta_coll.schedule_retry(bnum=bnum):
                    self.job_meta_coll.index_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                    self.job_data_coll.store_data(bnum=bnum, data=None,
                                                  is_done=True, is_reparse=False)
                return False

            for k,v in data.items():
                if k in merged_data:
                    raise Exception("duplicate key: {}".format(k))
                merged_data[k] = v

        if not merged_data and not is_reparse:
            self.logger.info("no data")
            # Make an entry indicating there are no data for this build.
            self.job_meta_coll.index_data(bnum=bnum, data=None,
                                          is_done=is_done, is_reparse=is_reparse)
            self.job_data_coll.store_data(bnum=bnum, data=None,
                                          is_done=is_done, is_reparse=is_reparse)
            return False

        # index_data may side-effect merged_data by extracting "private" stuff
        # (e.g. "commands" like "_add_to_meta_list") so call it first!
        #
        # XXXrs - CONSIDER - this "private" "command" hints that
        #         might want custom post-aggregation "indexers" that
        #         are paired with the "aggregators".
        #

        self.job_meta_coll.index_data(bnum=bnum, data=merged_data,
                                      is_done=is_done, is_reparse=is_reparse)
        self.job_data_coll.store_data(bnum=bnum, data=merged_data,
                                      is_done=is_done, is_reparse=is_reparse)
        self.alljob_idx.index_data(job_name=self.job_name,
                                   bnum=bnum, data=merged_data,
                                   is_done=is_done, is_reparse=is_reparse)

        host_data_coll = JenkinsHostDataCollection(jmdb=jmdb, host_name=merged_data['built_on'])
        host_data_coll.store_data(job_name=self.job_name, bnum=bnum, data=merged_data,
                                  is_done=is_done, is_reparse=is_reparse)
        self.logger.debug("end")
        return True

    def _postprocess_job(self, *, test_mode=False, default_only=False):
        postprocessors = [JenkinsJobPostprocessor(jenkins_host=self.jenkins_host, job_name=self.job_name)]
        if not default_only:
            if self.postprocessor_plugins:
                postprocessors.extend(self.postprocessor_plugins)
        for pproc in postprocessors:
            try:
                data = pproc.update_job(test_mode=test_mode)
                self.job_meta_coll.store_data(key=pproc.name, data=data)
            except Exception as e:
                self.logger.exception("exception post-processing job: {}"
                                      .format(self.job_name))

    def _do_updates(self, *, builds, test_mode=False,
                                     test_data_path=None,
                                     force_default_job_update=False,
                                     is_reparse=False ):
        self.logger.info("builds: {}".format(builds))
        self.logger.info("test_mode: {}".format(test_mode))
        self.logger.info("test_data_path: {}".format(test_data_path))
        self.logger.info("is_reparse: {}".format(is_reparse))
        updated = 0
        for bnum in builds:
            if self._update_build(bnum=bnum, test_mode=test_mode,
                                  test_data_path=test_data_path,
                                  is_reparse=is_reparse):
                updated += 1
        if updated:
            self.logger.debug("{} builds updated, call postprocessors".format(updated))
            self._postprocess_job(test_mode=test_mode)
        elif force_default_job_update:
            self._postprocess_job(test_mode=test_mode, default_only=True)
        return updated


    def update_builds(self, *, test_builds=None,
                               test_data_path=None,
                               force_default_job_update=False):
        self.logger.info("start")

        if test_builds:
            self._do_updates(builds=test_builds,
                             test_mode=True,
                             test_data_path=test_data_path)
            return

        jobinfo = self.japi.get_job_info(job_name=self.job_name)
        jenkins_first = jobinfo.first_build_number()
        jenkins_last = jobinfo.last_build_number()
        if not jenkins_first or not jenkins_last:
            self.logger.error("missing first or last build for job {}".format(self.job_name))
            return

        pending = self.job_meta_coll.pending_builds(first=jenkins_first, last=jenkins_last)
        updated = self._do_updates(builds=pending[:self.builds_max], force_default_job_update=force_default_job_update)

        extra = self.builds_max - updated

        # We can do up to "extra" reparse.
        if extra > 0:
            reparse = self.job_meta_coll.reparse(rtnmax=extra)
            if reparse:
                self._do_updates(builds=reparse, is_reparse=True)

# MAIN -----

cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                        'JENKINS_HOST': {'default': None},
                        'JENKINS_DB_NAME': {'default': None},
                        'UPDATE_JOB_LIST': {'default': None},
                        'ALL_JOB_UPDATE_FREQ_HR': {'default': 24}})

# It's log, it's log... :)
logging.basicConfig(level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)


import argparse
parser = argparse.ArgumentParser()
parser.add_argument("-b", help="test mode build number", metavar="bnum",
                    dest='test_builds', action='append', default=[])
parser.add_argument("-j", help="test mode job name", metavar="name",
                    dest='update_jobs', action='append', default=[])
parser.add_argument("-p", help="path to test mode build info.json", metavar="path",
                    dest='test_data_path', default=None)
args = parser.parse_args()

test_mode = False
if len(args.test_builds):
    if len(args.update_jobs) != 1:
        parser.print_help()
        raise ValueError("To activate test mode, exactly one update_job (-j)"
                         " and at least one test_build (-b) are required")
    test_mode = True
    if not cfg.get('JENKINS_DB_NAME'):
        raise ValueError("test mode requires JENKINS_DB_NAME")

jmdb = JenkinsMongoDB()
logger.info("jmdb {}".format(jmdb))

try:
    # Clear any expired alerts
    AlertManager().clear_expired()
except Exception:
    logger.error("Exception while clearing expired alerts",
                 exc_info=True)

process_lock = None
try:
    aggregator_plugins = AggregatorPlugins()
    postprocessor_plugins = PostprocessorPlugins()

    jenkins_host=cfg.get('JENKINS_HOST')
    if not jenkins_host:
        raise ValueError("JENKINS_HOST not defined")
    logger.info("using jenkins_host {}".format(jenkins_host))

    force_default_job_update = False
    job_list = args.update_jobs
    if not job_list:
        logger.info("no job list, fetching all known jobs")
        japi = JenkinsApi(host=jenkins_host)
        job_list = japi.list_jobs()

        # Update the active jobs and active hosts lists in the DB
        logger.info("updating active jobs list in DB")
        jmdb.active_jobs(job_list=job_list)
        logger.info("updating active hosts list in DB")
        jmdb.active_hosts(host_list=japi.list_hosts())

        # Since we're doing the full list, see if we need to force
        # a default update of job stats.  A force update will ensure the
        # job stats are maintained even if there are no recent builds for
        # that job. (ENG-8959)
        ts = jmdb.all_job_update_ts()
        if int(time.time()) > ts:
            force_default_job_update = True

    logger.info("job list: {}".format(job_list))
    logger.info("force_default_job_update: {}"
                .format(force_default_job_update))

    for job_name in job_list:
        logger.info("process {}".format(job_name))

        # Try to obtain the process lock
        process_lock_name = "{}_process_lock".format(job_name)
        process_lock_meta = {"reason": "locked by JenkinsJobAggregators for update_builds()"}
        process_lock = MongoDBKeepAliveLock(db=jmdb.jenkins_db(), name=process_lock_name)
        try:
            process_lock.lock(meta=process_lock_meta)
        except MongoDBKALockTimeout as e:
            logger.info("timeout acquiring {}".format(process_lock_name))
            continue

        jja = JenkinsJobAggregators(jenkins_host=jenkins_host,
                                    job_name=job_name, jmdb=jmdb,
                                    aggregator_plugins=aggregator_plugins.by_job(job_name=job_name),
                                    postprocessor_plugins=postprocessor_plugins.by_job(job_name=job_name))
        jja.update_builds(test_builds=args.test_builds,
                          test_data_path=args.test_data_path,
                          force_default_job_update=force_default_job_update)
        process_lock.unlock()

    if force_default_job_update:
        next_force = int(time.time() + (cfg.get('ALL_JOB_UPDATE_FREQ_HR')*3600))
        logger.info("set next force_default_job_update: {}".format(next_force))
        jmdb.all_job_update_ts(ts=next_force)


except Exception as e:
    # XXXrs - FUTURE - context manager for keep-alive lock
    if process_lock is not None:
        process_lock.unlock()
    raise
