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

AGGREGATOR_PLUGINS = [{'class_name': 'XDFuncTestLogParser',
                       'job_names': ['XDFuncTest']}]

class XDFuncTestLogParserException(Exception):
    pass

class XDFuncTestLogParser(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         send_log_to_update=True)
        self.logger = logging.getLogger(__name__)
        self.user_to_cur_iter = {}
        self.user_to_iters = {}
        self.functests_data = {}


    def _get_timestamp_ms(self, *, fields):
        try:
            return int(self.start_time_ms+(float(fields[0])*1000))
        except ValueError:
            self.logger.exception("timestamp parse error: {}".format(line))
            return None


    def _ts_ms_user(self, *, fields):
        return(self._get_timestamp_ms(fields=fields), fields[1])


    def _end_current_iter(self, *, fields, result):
        ts_ms, user = self._ts_ms_user(fields=fields)
        cur = self.user_to_cur_iter.get(user, None)
        if cur is not None:
            # We just finished cur, so calc the duration and stash
            cur['duration_ms'] = ts_ms - cur['start_time_ms']
            cur['result'] = result
            self.user_to_iters.setdefault(user, []).append(cur)
            self.user_to_cur_iter.pop(user)


    def _do_update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Parse the log for sub-test info.
        """
        self.start_time_ms = jbi.start_time_ms()

        user_to_cur_testcase = {}
        for lnum, line in enumerate(log.splitlines()):
            fields = line.split()

            if len(fields) < 5:
                continue

            '''
            132.997 admin1 JSHandle:ok 
            '''
            if fields[2] == "JSHandle:ok":
                # End of a last random step (iteration).
                self._end_current_iter(fields=fields, result='pass')

                # Pass marker for a complete set of functional test iterations.

            '''
            325.010. admin2 JSHandle:not ok 434 - Test "XD Func Tests" failed (Fail to delete workbook admin2-wkbk-FuncTest68005 after 10 tries)
            '''

            if fields[2] == "JSHandle:not" and fields[3] == "ok":
                # End of any previous random step (iteration).
                self._end_current_iter(fields=fields, result='fail')

                # Fail marker for a complete set of functional test iterations.
                # XXXrs - WORKING HERE

            '''
            132.993 admin1 JSHandle:XD Functests passed with " 500 " runs ! The seed is 159596996684311
            or
            157.191 admin2 JSHandle:XD Functests failed in " 434 " runs ! The seed is 159596763355670
            '''
            if "The seed is" in line and fields[2] == "JSHandle:XD":
                # End of functests set

                result = fields[4][:-2]
                self._end_current_iter(fields=fields, result=result)

                ts_ms, user = self._ts_ms_user(fields=fields)
                iters = self.user_to_iters.get(user, None) or []
                if user in self.user_to_iters[user]:
                    self.user_to_iters.pop(user)
                if user in self.user_to_cur_iter:
                    self.user_to_cur_iter.pop(user)
                count = fields[7]
                seed = fields[-1]

                self.functests_data.setdefault(user, []).append(
                        {"iterations": iters,
                         "result": result,
                         "count": len(iters),
                         "seed": seed})
                continue

            '''
            1579.602  npm ERR! Test failed.  See above for more details.
            '''
            if "npm ERR!" in line:
                # Premature (?) exit, clean up any "in process"
                result = "fail"
                ts_ms = self._get_timestamp_ms(fields=fields)

                for user in self.user_to_cur_iter.keys():
                    cur = self.user_to_cur_iter.get(user, None)
                    if cur is not None:
                        # We just finished cur, so calc the duration and stash
                        cur['duration_ms'] = ts_ms - cur['start_time_ms']
                        cur['result'] = result
                        self.user_to_iters.setdefault(user, []).append(cur)
                self.user_to_cur_iter = {}

                for user in self.user_to_iters.keys():
                    iters = self.user_to_iters.get(user)
                    if iters is not None:
                        self.functests_data.setdefault(user, []).append(
                                        {"iterations": iters,
                                         "result": result,
                                         "count": len(iters),
                                         "seed": "UNKNOWN"})
                self.user_to_iters = {}

            '''
            121.401 admin1 JSHandle:Running the 0/500 iterations
            '''
            if fields[2] == "JSHandle:Running" and fields[-1] == "iterations":

                # End of any previous random step (iteration).
                self._end_current_iter(fields=fields, result='pass')

                # Initialize next random step (iteration).
                iteration = fields[4]
                try:
                    # sanity check
                    it,maxit = iteration.split('/')
                    it = int(it)
                    maxit = int(maxit)
                except:
                    raise XDFuncTestLogParserException(
                            "unparsable iteration identifier {}: {}"
                            .format(lnum, line))

                self.user_to_cur_iter[fields[1]] = {'iteration': iteration}
                continue

            '''
            212.412 admin1 JSHandle:XDFuncTest log: take action createNewWorkbook
            '''
            # Start and identify the current random step (iteration).
            if fields[4] == "take" and fields[5] == "action":
                ts_ms, user = self._ts_ms_user(fields=fields)
                action = " ".join(fields[6:])
                cur = self.user_to_cur_iter.get(user, None)
                if not cur:
                    raise XDFuncTestLogParserException(
                            "take action seen before iteration indicator {}: {}"
                            .format(lnum, line))
                cur['start_time_ms'] = ts_ms
                cur['action'] = action
                continue




        return {'xd_func_test_testcases': self.functests_data}


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
    parser.add_argument("--job", help="jenkins job name", default="XDFuncTest")
    parser.add_argument("--bnum", help="jenkins build number", default="1882")
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
        parser = XDFuncTestLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
