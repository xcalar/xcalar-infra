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

AGGREGATOR_PLUGINS = [{'class_name': 'FuncTestLogParser',
                       'job_names': ['__ALL__']}]


class FuncTestLogParserException(Exception):
    pass


# N.B. This parser relies on logging modifications that were added Sep. 2020
class FuncTestLogParser(JenkinsAggregatorBase):
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
        self.duration_ms = jbi.duration_ms()

        subtest_data = {}
        cur_subtest = None

        for lnum, line in enumerate(log.splitlines()):

            fields = line.split()
            if len(fields) < 3:
                continue

            if cur_subtest is not None:
                if fields[1] == 'Error:':
                    cur_subtest['result'] = "Error"
                    cur_subtest['reason'] = " ".join(fields[3:])
                    continue
                elif fields[1] == "SUBTEST_RESULT:" or fields[1] == "TESTCASE_RESULT:":
                    cur_subtest['result'] = " ".join(fields[3:])
                    continue
                else:
                    # If field[1] is our subtest name assume fields[3:] is result
                    name = fields[1][1:-1]
                    if name == cur_subtest['name']:
                        cur_subtest['result'] = " ".join(fields[3:]) # XXXrs
                        continue

            if fields[1] == "SUBTEST_START:" or fields[1] == "TESTCASE_START:":
                if cur_subtest is not None:
                    raise FuncTestLogParserException(
                            "nested TEST_START\n{}: {}".format(lnum, line))

                test_name = fields[2]
                test_id = MongoDB.encode_key(test_name)
                cur_subtest = {'name': test_name,
                               'id': test_id,
                               'start_time_ms': self._get_timestamp_ms(fields=fields)}
                continue

            if fields[1] == "SUBTEST_END:" or fields[1] == "TESTCASE_END:":
                if cur_subtest is None:
                    raise FuncTestLogParserException(
                            "TEST_END before TEST_START\n{}: {}"
                            .format(lnum, line))

                if fields[2] != cur_subtest['name']:
                    raise FuncTestLogParserException(
                            "unmatched TEST_END for {} while cur_subtest {}\n{}: {}"
                            .format(fields[2], cur_subtest, lnum, line))

                ts_ms = self._get_timestamp_ms(fields=fields)
                duration_ms = ts_ms - cur_subtest['start_time_ms']
                cur_subtest['duration_ms'] = duration_ms
                test_id = cur_subtest.pop('id')
                if test_id not in subtest_data:
                    subtest_data[test_id] = {}
                iteration = len(subtest_data[test_id].keys())+1
                subtest_data[test_id][str(iteration)] = cur_subtest
                cur_subtest = None
                continue

            if cur_subtest is None:
                continue

            if fields[1] == "NumTests:":
                try:
                    cnt = int(fields[2])
                except ValueError:
                    raise FuncTestLogParserException(
                            "non-integer NumTests value\n{}: {}".format(lnum, line))
                if cnt > 1:
                    raise FuncTestLogParserException(
                            "unexpected NumTests value\n{}: {}".format(lnum, line))
                if cnt == 0:
                    cur_subtest['result'] = "Skip" # XXXrs ?!?

        return {'functest_subtests': subtest_data}


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
    parser.add_argument("--job", help="jenkins job name", default="FuncTestTrigger")
    parser.add_argument("--bnum", help="jenkins build number", default="15352")
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
        parser = FuncTestLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
