#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import logging
import os
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.mongo import MongoDB

AGGREGATOR_PLUGINS = [{'class_name': 'XcTestHarnessLogParser',
                       'job_names': ['__ALL__']}]


class XcTestHarnessLogParserException(Exception):
    pass


class XcTestHarnessLogParser(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         send_log_to_update=True)
        self.logger = logging.getLogger(__name__)


    def _test_description(self, *, fields):
        dfields = None
        for field in fields:
            if dfields is not None:
                dfields.append(field)
                if field[-1] == '\"':
                    break
            if field == "Test":
                dfields = []
        if not dfields:
            return None
        return " ".join(dfields)[1:-1]


    def _init_subtest_data(self, *, data, result, fields):
        """
        If no ID conflict, inserts initial subtest dictionary into data dictionary
        and returns the reference to the subtest dictionary for caller to modify
        further (as needed).
        """
        description = self._test_description(fields=fields)
        if not description:
            subtest_id = MongoDB.encode_key(fields[2])
            name = fields[2]
            number = None
        else:
            subtest_id = MongoDB.encode_key("{}:{}".format(fields[2],fields[3]))
            name = fields[2]
            number = fields[3]

        if subtest_id in data:
            raise XcTestHarnessLogParserException("duplicate subtest ID: {}".format(subtest_id))

        data[subtest_id] = {'name': name,
                            'number': number,
                            'result': result,
                            'description': description}
        return data[subtest_id]

    def _parse_pass(self, *, data, timestamp_ms, fields):
        """
        Variations on PASS:
            A) 795.142  PASS: libhashSanity 0 - Test "FNV Tests" passed in 0.000s
            B) 2414.373  PASS: localSystemTest.sh 5 - Test "(user0) Simple Join Test"
            C) 1713.879  PASS: mgmtdtest.sh 69 - Test "except" passed
        """

        # Covers B) and C)  Trailing "passed" uninteresting
        subtest_data = self._init_subtest_data(data=data, result="PASS", fields=fields)

        if len(fields) > 3 and fields[-3] == "passed" and fields[-2] == "in":
            # A)
            duration_ms = int(float(fields[-1][:-1])*1000)
            subtest_data['duration_ms'] = duration_ms
            subtest_data['start_time_ms'] = timestamp_ms-duration_ms


    def _parse_fail(self, *, data, timestamp_ms, fields):
        """
        Variations on FAIL:
            A) 1785.787  FAIL: libapissanity.sh returned 1
            B) 5151.483  FAIL: localSystemTest.sh 2 - Test "(user0) Query Regression Test Suite"

            C) 6328.162  FAIL: mgmtdtest.sh 65 - Test "union" failed ({"httpStatus":0})
            D) 1030.520  FAIL: libdagsanity failed with SIGTERM
            E) 6469.229  FAIL: sessionReplayTest.sh 0 - Test "gracefully shutdown test" failed in 663.347s

        """
        subtest_data = self._init_subtest_data(data=data, result="FAIL", fields=fields)

        failed_idx = None
        for i in range(len(fields)):
            if fields[i] == "failed":
                failed_idx = i
                break

        if failed_idx is not None:
            # C) through E)
            next_idx = failed_idx+1
            if next_idx < len(fields):
                if fields[next_idx] == "with" and next_idx + 1 < len(fields):
                    # D)
                    subtest_data['reason'] = " ".join(fields[next_idx+1:])
                elif fields[next_idx] == "in":
                    # E)
                    duration_ms = int(float(fields[-1][:-1])*1000)
                    subtest_data['duration_ms'] = duration_ms
                    subtest_data['start_time_ms'] = timestamp_ms-duration_ms
                else:
                    # C)
                    subtest_data['reason'] = " ".join(fields[next_idx:])

        elif subtest_data['description'] is None:
            # A)
            subtest_data['reason'] = " ".join(fields[3:])
        # else B) nothing more to add


    def _parse_skip(self, *, data, timestamp_ms, fields):
        """
        Variations on SKIP:
            A) 1427.803  SKIP: libbcsanity 1 - Test "Lookaside test" disabled # SKIP
        """
        self._init_subtest_data(data=data, result="SKIP", fields=fields)


    def _do_update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Parse the log for sub-test info.
        """
        self.start_time_ms = jbi.start_time_ms()
        self.duration_ms = jbi.duration_ms()

        saw_start_marker = False
        subtest_data = {}
        for line in log.splitlines():

            # Look for test completion signatures
            """
            795.136  (cd "/home/jenkins/workspace/XCETest/buildOut/src/lib/tests" && ./libhashSanity)
            795.136  stderr -> /tmp/tmpj49og38o
            795.142  # "FNV Tests"
            795.142
            795.142  PASS: libhashSanity 0 - Test "FNV Tests" passed in 0.000s
            795.142  SKIP: libhashSanity 1 - Test "CRC32c Tests" disabled # SKIP
            """

            fields = line.split()
            if len(fields) < 2:
                continue

            if fields[1] != "PASS:" and fields[1] != "FAIL:" and fields[1] != "SKIP:":
                continue

            try:
                timestamp_ms = int(self.start_time_ms+(float(fields[0])*1000))
            except ValueError:
                self.logger.exception("timestamp parse error: {}".format(line))
                continue

            #print(line)

            try:
                if fields[1] == "PASS:":
                    self._parse_pass(data=subtest_data,
                                     timestamp_ms=timestamp_ms,
                                     fields=fields)
                elif fields[1] == "FAIL:":
                    self._parse_fail(data=subtest_data,
                                     timestamp_ms=timestamp_ms,
                                     fields=fields)
                elif fields[1] == "SKIP:":
                    self._parse_skip(data=subtest_data,
                                     timestamp_ms=timestamp_ms,
                                     fields=fields)
            except:
                self.logger.exception("parse error: {}".format(line))

        return {'xc_test_harness_subtests': subtest_data}


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
    parser.add_argument("--job", help="jenkins job name", default="XCETest")
    parser.add_argument("--bnum", help="jenkins build number", default="49921")
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
        parser = XcTestHarnessLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        result = jbi.result()
        print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
        data = parser.update_build(jbi=jbi, log=jbi.console())
        pprint(data)
