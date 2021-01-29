#!/usr/bin/env python

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.
#

import argparse
import json
import logging
import os
import re
import socket
import sys
import threading
import time
import traceback

infradir = os.environ.get('XLRINFRADIR', '')

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from xcalar.external.LegacyApi.XcalarApi import XcalarApi, XcalarApiStatusException
from xcalar.external.client import Client

from py_common.dlogger import DLogger

class DataflowJobFail(Exception):
    pass

class DataflowEngine(object):

    def __init__(self, *, test_id, host, port, user, password, cfg_path):

        self.logger = logging.getLogger(__name__)
        self.data_logger = DLogger(test_id=test_id)
        self.logger.info("STARTING")

        with open(cfg_path) as fd:
            cfg = json.load(fd)

        self.name = cfg.get('name')
        self.logger.info("Running configuration: {}".format(self.name))

        self.xcalar_url = "https://{}:{}".format(host, port)
        self.client_secrets = {'xiusername': user, 'xipassword': password}
        self.xcalar_api = XcalarApi(url=self.xcalar_url, client_secrets=self.client_secrets)
        self.client = Client(url=self.xcalar_url, client_secrets=self.client_secrets)

        self.workbook_path = cfg.get('workbook_path')
        self.workbook_name = cfg.get('workbook_name')
        self.data_target_name = cfg.get('data_target_name')
        self.dataflow_name = cfg.get('dataflow_name')
        self.dataflow_params = cfg.get('dataflow_params')

        try:
            workbook = self.client.get_workbook(workbook_name=self.workbook_name)
            self.logger.info("deleting pre-existing workbook")
            workbook.delete()
        except:
            pass

        with open(self.workbook_path, 'rb') as wbfd:
            self.logger.info("uploading workbook")
            self.workbook = self.client.upload_workbook(
                                workbook_name=self.workbook_name,
                                workbook_content=wbfd.read())
        self.xcalar_api.setSession(self.workbook)

        if self.data_target_name is not None:
            try:
                data_target = self.client.get_data_target(target_name=self.data_target_name)
                self.logger.info("deleting pre-existing data target")
                data_target.delete()
            except:
                pass

            self.logger.info("adding data target")
            self.data_target = self.client.add_data_target(
                                                target_name = self.data_target_name,
                                                target_type_id = cfg.get('data_target_type_id'),
                                                params = cfg.get('data_target_params'))

        self.logger.info("activating workbook")
        self.session = self.workbook.activate()

        self.dataflow_names = self.workbook.list_dataflows()
        self.logger.info("dataflow names in workbook: {}".format(self.dataflow_names))


    def _execute_df(self, *, job_name, dataflow_name, dataflow_params):
        self.logger.info("STARTING")

        self.logger.info("getting dataflow: {}".format(dataflow_name))
        dataflow = self.workbook.get_dataflow(dataflow_name, params=dataflow_params)

        self.logger.info("executing job_name: {}".format(job_name))
        result = self.session.execute_dataflow(dataflow, query_name=job_name, optimized=True)


    def start_jobs(self, *, batch, instances):
        self.logger.info("STARTING")

        job_tag = "Xcalar_{}".format(int(time.time()))
        for instance in range(instances):
            job_name = "{}_batch{}_instance{}".format(job_tag, batch, instance)
            self._execute_df(job_name = job_name,
                             dataflow_name = self.dataflow_name,
                             dataflow_params = self.dataflow_params)
        return job_tag


    def _check_jobs(self, *, job_tag, job_states):
        q_pending = False
        q_num_done=0
        q_num_pending=0
        qs = self.xcalar_api.listQueries("*{}*".format(job_tag))
        for q in qs.queries:
            prior_state = job_states.get(q.name, "Uninitialized")
            if q.state != prior_state:
                self.data_logger.log(data_type="TEST_EVENT",
                                     data_label="JOB_STATE_TRANSITION",
                                     dikt={"job_name": q.name,
                                           "prior_state": prior_state,
                                           "new_state": q.state})
            job_states[q.name] = q.state

            if q.state == 'qrFinished' or q.state == 'qrCancelled':
                self.logger.info("job {} is DONE".format(q.name))
                q_num_done = q_num_done + 1

            elif q.state == 'qrError':
                raise DataflowJobFail("job/query {} ERROR".format(q.name))

            else:
                self.logger.info("job {} is NOT done {}".format(q.name, q.state))
                q_num_pending = q_num_pending + 1
                q_pending = True
        self.logger.info("job status: {} done {} pending\n"
                         .format(q_num_done, q_num_pending))
        return q_pending

    def _match_pats(self, *, s, pats):
        for pat in pats:
            if pat.match(s):
                return True
        return False

    def wait_for_jobs(self, *, job_tag):
        self.logger.info("STARTING")
        check_interval = 10 # parameterize?

        now = int(time.time())
        next_check_time = now + check_interval
        job_states = {}

        while True:
            time.sleep(1)
            now = int(time.time())

            if now >= next_check_time:
                if not self._check_jobs(job_tag=job_tag,
                                        job_states=job_states):
                    # No jobs pending, we're done!
                    return
                next_check_time = now + check_interval

    def cleanup_jobs(self, *, job_tag):
        self.logger.info("STARTING")
        qs = self.xcalar_api.listQueries("*{}*".format(job_tag))
        q_pending = True
        while q_pending:
            q_pending = False
            for q in qs.queries:
                if q.state == 'qrProcessing':
                    # Shouldn't get here :/
                    self.logger.info("cancel job {}".format(q.name))
                    self.xcalar_api.cancelQuery(q.name)
                    q_pending = True
                else:
                    self.logger.info("deleting job {}".format(q.name))
                    self.xcalar_api.deleteQuery(q.name)


    def run(self, *, batches, instances):

        start_time = time.time()
        self.data_logger.log(data_type="TEST_EVENT", data_label="TEST_START")
        for batch in range(batches):
            job_tag = self.start_jobs(batch=batch, instances=instances)
            self.wait_for_jobs(job_tag=job_tag)
            self.cleanup_jobs(job_tag=job_tag)
        self.data_logger.log(data_type="TEST_EVENT", data_label="TEST_END")
        self.logger.info("Test Duration: {}".format(int(time.time() - start_time)))


    def cleanup(self):
        self.logger.info("STARTING")
        self.session.destroy()
        self.xcalar_api.setSession(None)
        self.session = None
        self.sdk_session = None
        self.xcalar_api = None


if __name__ == "__main__":

    os.environ["XLR_PYSDK_VERIFY_SSL_CERT"] = "false"

    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger()

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, help="Xcalar hostname")
    parser.add_argument("--port", required=True, help="Xcalar API port")
    parser.add_argument("--user", required=True, help="User to run as")
    parser.add_argument("--pass", required=True, dest='password', help="User's password")
    parser.add_argument("--batches", required=True, type=int,
                        help="Number of Batches (loops)")
    parser.add_argument("--instances", required=True, type=int,
                        help="Number of parallel instances per batch")
    parser.add_argument("--config", required=True,
                        help="Path to JSON configuration file")
    parser.add_argument("--test_id", required=True, help="Test ID string")
    args = parser.parse_args()

    data_logger = DLogger(test_id=args.test_id)

    fail = False
    engine = None
    start_time = None
    end_time = None

    try:
        engine = DataflowEngine(host = args.host,
                                port = args.port,
                                user = args.user,
                                password = args.password,
                                cfg_path = args.config,
                                test_id = args.test_id)

    except Exception as exc:
        fail = True
        msg = "Unhandled exception during initialization"
        data_logger.exception(msg=msg, exc=exc, fatal=True)
        logger.exception("FAIL: {}".format(msg))

    if not fail:
        try:
            engine.run(batches=args.batches, instances=args.instances)

        except DataflowJobFail as exc:
            fail = True
            msg = "Dataflow job failure"
            data_logger.exception(msg=msg, exc=exc, fatal=True)
            logger.exception("FAIL: {}".format(msg))

        except Exception as exc:
            fail = True
            msg = "Unhandled exception"
            data_logger.exception(msg=msg, exc=exc, fatal=True)
            logger.exception("FAIL: {}".format(msg))

    if engine:
        try:
            engine.cleanup()
        except Exception as exc:
            # Cleanup failures don't fail the test.
            msg = "Unhandled exception during cleanup"
            data_logger.exception(msg=msg, exc=exc, fatal=False)
            logger.warn(msg, exc_info=True)

    if not fail:
        logger.info("SUCCESS")

    sys.exit(fail)
