#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import datetime
import logging
import os
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.jenkins_aggregators.update.alerting import AlertManager
from py_common.mongo import MongoDB

AGGREGATOR_PLUGINS = [{'class_name': 'CoreAnalyzerLogParser',
                       'job_names': ['__ALL__']}]


class CoreAnalyzerLogParserException(Exception):
    pass


class CoreAnalyzerLogParser(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         send_log_to_update=True)
        self.logger = logging.getLogger(__name__)


    def _store_cur_core(self, *, cores, cur_core):
        # Trim off any path prefix
        corefile_name = cur_core.get('corefile_name')
        if '/' in corefile_name:
            cur_core['corefile_name'] = corefile_name.split('/')[-1]
        key = MongoDB.encode_key(cur_core.get('corefile_name'))
        cores[key] = cur_core


    def _do_update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Parse the log for analyzed core information
        """
        cores = {}
        cur_core = None

        for lnum, line in enumerate(log.splitlines()):

            fields = line.split()
            if len(fields) < 4:
                continue

            # 2847.711 #### Analyzing buildOut/src/bin/usrnode/usrnode core.usrnode.7703 #####
            if '####' in fields[1] and fields[2] == 'Analyzing':
                if cur_core is not None:
                    self.logger.error("LOG PARSE ERROR")
                    self.logger.error("Analysis header before analysis footer line {}: {}"
                                      .format(lnum, line))
                    self.logger.error("Previous: {}".format(cur_core))
                    self._store_cur_core(cores=cores, cur_core=cur_core)

                cur_core = {'bin_path': fields[3], 'corefile_name': fields[4]}
                continue

            # 2847.730 Core was generated by `usrnode --nodeId 0 --numNodes 3 --configFile /home/jenkins/workspace/Controller'.
            if cur_core is not None and "Core was generated by" in line:
                cur_core['gen_by'] = " ".join(fields[5:])
                continue

            # 2847.882 Program terminated with signal SIGSEGV, Segmentation fault.
            if cur_core is not None and "Program terminated with" in line:
                cur_core['term_with'] = " ".join(fields[4:])
                continue

            # 2848.003 #### Done with buildOut/src/bin/usrnode/usrnode core.usrnode.7703 #####
            if '####' in fields[1] and fields[2] == 'Done' and fields[3] == 'with':
                if cur_core is None:
                    self.logger.error("LOG PARSE ERROR")
                    self.logger.error(
                            "Analysis footer before analysis header line {}: {}"
                            .format(lnum, line))
                    cur_core = {'bin_path': fields[4], 'corefile_name': fields[5]}

                if fields[4] != cur_core['bin_path']:
                    self.logger.error("LOG PARSE ERROR")
                    self.logger.error(
                            "Mismatch bin_path {} expected on line {}: {}"
                            .format(cur_core['bin_path'], lnum, line))
                    cur_core = {'bin_path': fields[4], 'corefile_name': fields[5]}

                if fields[5] != cur_core['corefile_name']:
                    self.logger.error("LOG PARSE ERROR")
                    self.logger.error(
                            "Mismatch corefile_name {} expected on line {}: {}"
                            .format(cur_core['corefile_name'], lnum, line))
                    cur_core = {'bin_path': fields[4], 'corefile_name': fields[5]}

                self._store_cur_core(cores=cores, cur_core=cur_core)
                cur_core = None
                continue

        return {'analyzed_cores': cores}


    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        try:
            data = self._do_update_build(jbi=jbi, log=log,
                                         is_reparse=is_reparse,
                                         test_mode=test_mode)
        except:
            self.logger.error("LOG PARSE ERROR", exc_info=True)

        if data is None:
            return None

        cores = data.get('analyzed_cores', None)
        if not cores:
            self.logger.info("no cores detected")
            return data

        if is_reparse:
            self.logger.info("suppressing alert on reparse")
            return data

        # Don't alert if we're running pre-checkin
        for key,val in jbi.parameters().items():
            if "REFSPEC" in key and "refs/changes" in val:
                send_alert = False
                self.logger.info("suppressing alert on change refspec: {}"
                                 .format(val))
                return data

        self.logger.info("sending alert")
        ts = int(jbi.start_time_ms()/1000)
        dt = datetime.datetime.fromtimestamp(ts)
        date_str = "{}-{:02d}-{:02d} {:02d}:{:02d}:{:02d}"\
                   .format(dt.year, dt.month, dt.day,
                           dt.hour, dt.minute, dt.second)

        labels = {'Date': date_str, 'URL':jbi.build_url}

        for key,item in cores.items():
            label_name = item.get('corefile_name', 'UnknownName')
            label_name = label_name.replace('.', '_')
            labels[label_name] = item.get('term_with', 'UnknownCause')

        job_name = jbi.job_name
        bnum = jbi.build_number
        alert_id="{}:{}".format(job_name, bnum)
        description="Jenkins job {} build {} detected core files"\
                    .format(job_name, bnum)
        AlertManager().critical(alert_group="corefile_detected",
                                alert_id=alert_id,
                                description=description,
                                labels = labels,
                                ttl=3600) # ample time to be noticed
        return data


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
    parser.add_argument("--bnum", help="jenkins build number", default="50949")
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
        parser = CoreAnalyzerLogParser(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        log = jbi.console()
        result = jbi.result()
        if args.log:
            print(log)
        else:
            print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
            data = parser.update_build(jbi=jbi, log=jbi.console())
            pprint(data)
