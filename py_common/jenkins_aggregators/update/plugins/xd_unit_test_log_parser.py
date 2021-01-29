#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import json
import logging
import os
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.mongo import MongoDB

AGGREGATOR_PLUGINS = [{'class_name': 'XDUnitTestLogParser',
                       'job_names': ['XDUnitTest']}]

class XDUnitTestLogParserException(Exception):
    pass

class XDUnitTestLogParser(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         send_log_to_update=True)
        self.logger = logging.getLogger(__name__)


    def _get_timestamp_ms(self, *, fields):
        try:
            return int(self.start_time_ms+(float(fields[0])*1000))
        except ValueError:
            self.logger.exception("timestamp parse error: {}".format(line))
            return None


    def _do_update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Parse the log for sub-test info.
        """
        self.start_time_ms = jbi.start_time_ms()

        testcase_data = {}
        for lnum, line in enumerate(log.splitlines()):
            '''
            631.088 JSHandle:[XDUnitTest] (3259) ColSchemaSection Test/_removeList should work: begin
            631.191 JSHandle:[XDUnitTest] (3259) ColSchemaSection Test/_removeList should work: pass(0.1s)


            632.127 JSHandle:[XDUnitTest] (3262) FileBrowser2 Test/renders a list of files: begin
            632.221 Warning uncaught execption: [Error: AssertionError]
            632.224 JSHandle:Test is still 99% completed
            632.229 JSHandle:[XDUnitTest] (3262) FileBrowser2 Test/renders a list of files: fail(50.1s)
            '''

            fields = line.split()

            if len(fields) < 3:
                continue

            if fields[1] != "JSHandle:[XDUnitTest]":
                continue

            '''
            632.230 JSHandle:[XDUnitTest] stats={"fail":1,"pass":3241}
            '''

            if "stats=" in fields[2]:
                foo,data = fields[2].split('=')
                stats = json.loads(data)
                testcase_data['stats'] = stats
                continue


            last = fields[-1]
            if "pass" not in last and "fail" not in last:
                continue

            result,more = last.split('(')
            duration_ms = int(float(more[:-2])*1000) # Strip trailing "s)"
            start_time_ms = self._get_timestamp_ms(fields=fields)-duration_ms

            testcase_num = fields[2][1:-1] # Sequence number with parenthesis stripped
            testcase_name = " ".join(fields[3:-1])

            testcase_data[testcase_num] = {"name": testcase_name,
                                           "number": testcase_num,
                                           "result": result,
                                           "start_time_ms": start_time_ms,
                                           "duration_ms": duration_ms}

        return {'xd_unit_test_testcases': testcase_data}


    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        try:
            return self._do_update_build(jbi=jbi, log=log,
                                         is_reparse=is_reparse,
                                         test_mode=test_mode)
        except:
            self.logger.error("LOG PARSE ERROR", exc_info=True)


# In-line "unit test"
if __name__ == '__main__':
    import argparse
    from pprint import pprint, pformat
    from py_common.jenkins_api import JenkinsApi, JenkinsBuildInfo

    # It's log, it's log... :)
    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout)])


    parser = argparse.ArgumentParser()
    parser.add_argument("--job", help="jenkins job name", default="XDUnitTest")
    parser.add_argument("--bnum", help="jenkins build number", default="15483")
    parser.add_argument("--log", help="just print out the log", action="store_true")
    args = parser.parse_args()

    test_builds = []
    builds = args.bnum.split(':')
    if len(builds) == 1:
        test_builds.append((args.job, args.bnum))
    else:
        for bnum in range(int(builds[0]), int(builds[1])+1):
            test_builds.append((args.job, bnum))

    japi = JenkinsApi(host='jenkins.int.xcalar.com')

    for job_name,build_number in test_builds:
        parser = XDUnitTestLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
