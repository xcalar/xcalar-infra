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

AGGREGATOR_PLUGINS = [{'class_name': 'XDTestSuiteLogParser',
                       'job_names': ['XDTestSuite']}]


class XDTestSuiteLogParserException(Exception):
    pass


class XDTestSuiteLogParser(JenkinsAggregatorBase):
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

        cur_test = None
        start_time_ms = None
        pass_summary_next = False
        pass_duration_next = False

        testcase_data = {}

        for lnum, line in enumerate(log.splitlines()):


            '''
            151.544 JSHandle:====================Test
            151.545 JSHandle:1
            151.547 JSHandle: Begin====================
            '''
            if "Begin===" in line:
                if start_time_ms is not None:
                    raise XDTestSuiteLogParserException(
                            "double Begin=== at line {}"
                            .format(lnum))
                fields = line.split()
                start_time_ms = self._get_timestamp_ms(fields=fields)
                continue

            if start_time_ms is None:
                continue

            fields = line.split()
            if len(fields) < 2:
                continue

            '''
            185.244 JSHandle:1 - Test "FlightTest" passed
            '''
            if pass_summary_next:
                pass_summary_next = False
                foo,tnum = fields[1].split(':')
                i = int(tnum) # validate integer
                result = fields[-1]
                assert(result == "passed")
                assert(cur_test is None)
                cur_test = {"number": tnum,
                            "name": " ".join(fields[4:-1])[1:-1],
                            "result": "pass",
                            "start_time_ms": start_time_ms}
                pass_duration_next = True
                continue

            '''
            185.245 JSHandle:Time taken: 33.686s
            '''
            if pass_duration_next:
                pass_duration_next = False
                assert("Time taken:" in line)
                assert(fields[-1][-1] == 's')
                duration = float(fields[-1][:-1])
                cur_test['duration_ms'] = int(duration*1000)
                testcase_data[cur_test.pop("number")] = cur_test
                cur_test = None
                start_time_ms = None
                continue

            if fields[1] == "JSHandle:ok":
                pass_summary_next = True
                continue

            '''
            906.601  JSHandle:not ok 1 - Test "FlightTest" failed (TypeError: Cannot read property 'length' of null)
            '''
            if fields[1] == "JSHandle:not" and fields[2] == "ok":

                tnum = fields[3]
                i = int(tnum) # validate int
                fail_time_ms = self._get_timestamp_ms(fields=fields)
                idx = fields.index("failed")
                reason = " ".join(fields[idx+1:])
                testcase_data[tnum] = {"name": " ".join(fields[6:idx])[1:-1],
                                       "result": "fail",
                                       "start_time_ms": start_time_ms,
                                       "duration_ms": fail_time_ms - start_time_ms,
                                       "reason": reason}
                continue

        return {'xd_test_suite_testcases': testcase_data}


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
    parser.add_argument("--job", help="jenkins job name", default="XDTestSuite")
    parser.add_argument("--bnum", help="jenkins build number", default="17042")
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
        parser = XDTestSuiteLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
