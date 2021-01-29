#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import logging
import os
import shlex
import subprocess
import tarfile
import tempfile
import sys


if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.mongo import MongoDB


AGGREGATOR_PLUGINS = [{'class_name': 'SystemStatsPlotter',
                       'job_names': ['__ALL__']}]


cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                        'PLOTTER_PATH': {'default': None},
                        'DEFAULT_PLOT_CFG_PATH': {'default': None}})


class SystemStatsPlotterException(Exception):
    pass


class SystemStatsPlotter(JenkinsAggregatorBase):

    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__)
        self.logger = logging.getLogger(__name__)
        self.tmpdir = None
        self.plotter_path = cfg.get('PLOTTER_PATH')
        self.plot_cfg_path = cfg.get('DEFAULT_PLOT_CFG_PATH')
        if not self.plotter_path or not self.plot_cfg_path:
            self.logger.warning("plotter not configured")


    def _update_build(self, *, jbi, is_reparse=False, test_mode=False):

        if not self.plotter_path or not self.plot_cfg_path:
            return {}

        # Generate the path to the expected artifacts directory
        artifacts_dir = "/netstore/qa/jenkins/{}/{}".format(jbi.job_name, jbi.build_number)
        dsh_tarfile_path = os.path.join(artifacts_dir,
                                "var_opt_xcalar_DataflowStatsHistory.tar.gz")
        self.logger.info("tarfile: {}".format(dsh_tarfile_path))

        # See if there is a DataflowStatsHistory tar file
        if not os.path.exists(dsh_tarfile_path):
            self.logger.info("tarfile doesn't exist, nothing to do")
            return {}

        # Untar to a temporary location
        tar = tarfile.open(dsh_tarfile_path, 'r')
        self.tmpdir = tempfile.TemporaryDirectory()
        self.logger.info("tmpdir: {}".format(self.tmpdir.name))
        tar.extractall(self.tmpdir.name)
        dsh_dir = os.path.join(self.tmpdir.name, "var", "opt", "xcalar", "DataflowStatsHistory")
        self.logger.info("dsh_dir: {}".format(dsh_dir))

        # Determine start/end times of the run
        start_ts = int(jbi.start_time_ms()/1000)
        end_ts = int(start_ts + jbi.duration_ms()/1000)
        self.logger.info("start_ts: {}".format(start_ts))
        self.logger.info("end_ts:   {}".format(end_ts))

        # Create plots in the artifacts directory
        plotdir = os.path.join(artifacts_dir, 'plots')

        # Call the plot utility
        cmd = "{} --dsh {} --plotdir {} --cfg {} --start_ts {} --end_ts {}"\
              .format(self.plotter_path, dsh_dir,
                      plotdir, self.plot_cfg_path, start_ts, end_ts)
        self.logger.info("cmd: {}".format(cmd))
        subprocess.run(shlex.split(cmd)).check_returncode()

        return {'stats_plots': plotdir}


    def update_build(self, *, jbi, log=None, is_reparse=False, test_mode=False):
        try:
            rtn = self._update_build(jbi=jbi)
        except:
            self.logger.error("exception while attempting to plot statistics"
                              " for {} {}".format(jbi.job_name, jbi.build_number),
                              exc_info=True)
            rtn = {}
        return rtn


# In-line "unit test"
if __name__ == '__main__':
    import argparse
    from pprint import pprint, pformat
    from py_common.jenkins_api import JenkinsApi, JenkinsBuildInfo

    # It's log, it's log... :)
    logging.basicConfig(level=cfg.get('LOG_LEVEL'),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout)])

    parser = argparse.ArgumentParser()
    parser.add_argument("--job", help="jenkins job name", default="FuncTestTrigger")
    parser.add_argument("--bnum", help="jenkins build number", default="15352")
    args = parser.parse_args()

    test_builds = []
    builds = args.bnum.split(':')
    if len(builds) == 1:
        test_builds.append((args.job, args.bnum))
    else:
        for bnum in range(int(builds[0]), int(builds[1])+1):
            test_builds.append((args.job, bnum))

    japi = JenkinsApi(host='jenkins.int.xcalar.com') # <- should take environment config
    for job_name,build_number in test_builds:
        plotter = SystemStatsPlotter(job_name=job_name)
        jbi = JenkinsBuildInfo(job_name=job_name, build_number=build_number, japi=japi)
        result = jbi.result()
        print("checking job: {} build: {} result: {}".format(job_name, build_number, result))
        data = plotter.update_build(jbi=jbi)
        pprint(data)
