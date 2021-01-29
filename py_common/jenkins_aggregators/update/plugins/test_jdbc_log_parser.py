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

AGGREGATOR_PLUGINS = [{'class_name': 'TestJdbcLogParser',
                       'job_names': ['__ALL__']}]


class TestJdbcLogParserException(Exception):
    pass


# N.B. This parser relies on logging modifications that were added Sep. 2020
class TestJdbcLogParser(JenkinsAggregatorBase):
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

        for lnum, line in enumerate(log.splitlines()):

            if "======" not in line:
                continue

            fields = line.split()

            # 524.922  2020-09-16 03:00:32,304 root  INFO     ============ START xcTest loop 1/1 ============
            if "START" in fields and "loop" in fields:
                sidx = fields.index("START")
                lidx = fields.index("loop")
                test_name = " ".join(fields[sidx+1:lidx])
                linfo = fields[lidx+1]
                lnum,lmax = linfo.split('/')

                ts_ms = self._get_timestamp_ms(fields=fields)
                lkey = ":".join([test_name, linfo])
                subtest_data[lkey] = {'name': test_name,
                                      'loop': lnum,
                                      'loop_max': lmax,
                                      'start_time_ms': ts_ms}

            # 633.188  2020-09-16 03:02:20,570 root  INFO     ============ END xcTest loop 1/1 ============
            if "END" in fields and "loop" in fields:
                eidx = fields.index("END")
                lidx = fields.index("loop")
                test_name = " ".join(fields[sidx+1:lidx])
                linfo = fields[lidx+1]
                lnum,lmax = linfo.split('/')

                lkey = ":".join([test_name, linfo])
                if lkey not in subtest_data:
                    raise TestJdbcLogParserException("unmatched END at line {}: {}"
                                                     .format(lnum, line))

                data = subtest_data[lkey]
                start_time_ms = data.get("start_time_ms", None)
                if not start_time_ms:
                    raise TestJdbcLogParserException("no start time in subtest_data: {}"
                                                     .format(data))
                data["duration_ms"] = self._get_timestamp_ms(fields=fields)-start_time_ms


        return {'test_jdbc_subtests': subtest_data}


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
    parser.add_argument("--job", help="jenkins job name", default="BuildSqldfTestAggreagate")
    parser.add_argument("--bnum", help="jenkins build number", default="19982")
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
        parser = TestJdbcLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
