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
import re
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.mongo import MongoDB

AGGREGATOR_PLUGINS = [{'class_name': 'ExpServerTestLogParser',
                       'job_names': ['GerritExpServerTest']}]


class ExpServerTestLogParserException(Exception):
    pass


class ExpServerTestLogParser(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         send_log_to_update=True)
        self.logger = logging.getLogger(__name__)
        self.passing_pat = re.compile(r"\d+\.\d+.*\s(\d+) passing.*")
        self.pending_pat = re.compile(r"\d+\.\d+.*\s(\d+) pending.*")
        self.failing_pat = re.compile(r"\d+\.\d+.*\s(\d+) failing.*")
        self.duration_field_pat = re.compile(r"\((\d+)ms\)")


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

        in_expserver_test = False
        test_start_ms = None

        passing_cnt = 0
        reported_passing_cnt = None
        pending_cnt = 0
        reported_pending_cnt = None
        reported_failing_cnt = None

        testcase_info = []

        collect_fail_list = False
        collect_fail_num = None

        for lnum, line in enumerate(log.splitlines()):

            if collect_fail_list:
                fields = line.split()
                marker = "{})".format(collect_fail_num)
                if marker not in fields:
                    continue

                # XXXrs - Should collect "reason" but it's ugly and will
                #         just need to wait until (if ever) we get
                #         structured logging.
                idx = fields.index(marker)
                testcase_info.append(
                        {"name": " ".join(fields[idx+1:]).strip(':'),
                         "result": "fail"})

                collect_fail_num += 1
                if collect_fail_num > reported_failing_cnt:
                    collect_fail_list = False
                continue

            '''
            Start marker:

            3143.021  ExpServerTest START:1599629561099
            '''
            if "ExpServerTest START:" in line:
                in_expserver_test = True
                test_start_ms = self._get_timestamp_ms(fields=line.split())
                continue

            if not in_expserver_test:
                continue

            '''
            Epilog:

            3189.701  ExpServerTest: =============================== Coverage summary ===============================
            3189.701
            3189.702  ExpServerTest: Statements   : 37.53% ( 10217/27224 )
            3189.702
            3189.788  ExpServerTest: Branches     : 26.25% ( 3325/12668 )
            3189.788  Functions    : 37.64% ( 1554/4129 )
            3189.788  Lines        : 37.75% ( 10065/26662 )
            3189.788  ================================================================================
            3189.788
            3189.789  ExpServerTest exited with code 0
            '''

            '''
            End marker:

            3189.789  ExpServerTest END:1599629607801
            '''

            if "ExpServerTest END:" in line:
                in_expserver_test = False
                continue



            '''
            Summary:

            3188.439  ExpServerTest:   247 passing (27s)
            3188.439
            3188.439  ExpServerTest:   16 pending
            3188.439
            3188.439
            3189.701  ExpServerTest:
            3189.701


            Alternately, on fail:

            3224.194  ExpServerTest:   121 passing (1m)
            3224.194    1 failing
            3224.194
            3224.194    1) ExpServer Login Test Credential functions should work:
            3224.194       Error: Timeout of 5000ms exceeded. Bla bla bla mumble.
            '''

            match = self.passing_pat.match(line)
            if match:
                reported_passing_cnt = int(match.group(1))
                continue

            match = self.pending_pat.match(line)
            if match:
                reported_pending_cnt = int(match.group(1))
                continue

            match = self.failing_pat.match(line)
            if match:
                reported_failing_cnt = int(match.group(1))
                collect_fail_list = True
                collect_fail_num = 1
                continue


            fields = line.split()
            if len(fields) < 3:
                continue

            '''
            N.B.: It appears that the "ExpServerTest:" prefix can be missing.
                  I suspect multiple lines can be delivered to the "listener" at once
                  depending on timing.  Handle both cases.

            985.326  ExpServerTest:     ✓ mumble-foo should work
            987.755  ✓ mumble-foo should work
            '''
            if '✓' in fields:
                idx = fields.index('✓')
                if not test_start_ms:
                    raise ExpServerTestLogParserException(
                            "can't determine duration at line {}: {}"
                            .format(lnum, line))

                ts_ms = self._get_timestamp_ms(fields=fields)
                match = self.duration_field_pat.match(fields[-1])
                if match:
                    #name = " ".join(fields[idx+1:-1])
                    name = " ".join(fields[idx+1:])
                    duration_ms = int(match.group(1))
                    test_start_ms = ts_ms - duration_ms
                else:
                    # Need to infer a duration based on last start
                    name = " ".join(fields[idx+1:])
                    duration_ms = ts_ms - test_start_ms

                testcase_info.append(
                        {"name": name,
                         "result": "pass",
                         "start_time_ms": test_start_ms,
                         "duration_ms": duration_ms})
                test_start_ms = ts_ms
                passing_cnt += 1
                continue

            if '-' in fields:
                idx = fields.index('-')
                if idx > 2:
                    self.logger.warn("Ignoring assumed spurious pending (skip)"
                                     " marker at line {} index {}: {}"
                                     .format(lnum, idx, line))
                    continue
                name = " ".join(fields[idx+1:])
                testcase_info.append(
                        {"name": name,
                         "result": "skip"})
                test_start_ms = self._get_timestamp_ms(fields=fields)
                pending_cnt += 1



        if collect_fail_list:
            raise ExpServerTestLogParserException("EOF while collecting failures")

        if reported_pending_cnt is not None and pending_cnt != reported_pending_cnt:
            raise ExpServerTestLogParserException(
                    "pending_cnt {} reported_pending_cnt {}"
                    .format(pending_cnt, reported_pending_cnt))
        if reported_passing_cnt is not None and passing_cnt != reported_passing_cnt:
            raise ExpServerTestLogParserException(
                    "passing_cnt {} reported_passing_cnt {}"
                    .format(passing_cnt, reported_passing_cnt))

        testcase_data = {}
        for idx,info in enumerate(testcase_info):
            testcase_data[str(idx)] = info

        return {'expserver_test_testcases': testcase_data}


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
    parser.add_argument("--job", help="jenkins job name", default="GerritExpServerTest")
    parser.add_argument("--bnum", help="jenkins build number", default="10725")
    # Fail build 10635
    #parser.add_argument("--bnum", help="jenkins build number", default="10635")
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
        parser = ExpServerTestLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
