#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import glob
import logging
import os
import re

class XcalarStatsFileFinder(object):
    def __init__(self, *, dsh):
        self.dsh = dsh
        self.logger = logging.getLogger(__name__)

    def system_stats_files(self, *, start_ts, end_ts, nodes=None):
        # /foo/bar/DataflowStatsHistory/systemStats/2020-6-20/18/1592702381_node1_stats.json.gz
        paths_by_node = {}
        filename_pat = re.compile(r"(\d+)_node(\d+)_stats.json.*")
        for path in glob.glob('{}/**/*.json*'.format(os.path.join(self.dsh, "systemStats")), recursive=True):
            directory, filename = os.path.split(path)
            m = filename_pat.match(filename)
            if not m:
                self.logger.debug("FAIL TO MATCH: {}".format(filename))
                continue
            ts = float(m.group(1))
            node = m.group(2)
            # XXXrs - a little slop here since a file can contain multiple seconds...
            if ts < start_ts or ts > end_ts:
                continue
            if nodes and node not in nodes:
                continue
            paths_by_node.setdefault(node, []).append(path)
        return paths_by_node

    def job_stats_files(self, *, start_ts, end_ts):
        # /foo/bar/DataflowStatsHistory/jobStats/2020-06-13/6/1592053315-XcalarSDKOpt-5EE4CB0504DC68D3-tpchSess_1036913322_worker_45-q7-thr45-q7-admin-1592053156_3064544/job_stats.json.gz
        filepath_pat = re.compile(r".*/(\d+)-.*/job_stats.json.*")
        paths = []
        for path in glob.glob('{}/**/job_stats.json*'.format(os.path.join(self.dsh, "jobStats")), recursive=True):
            m = filepath_pat.match(path)
            if not m:
                self.logger.debug("FAIL TO MATCH: {}".format(path))
                continue
            ts = float(m.group(1))
            # XXXrs - a little slop here since a file can contain multiple seconds...
            if ts < start_ts or ts > end_ts:
                continue
            paths.append(path)
        return paths

if __name__ == "__main__":
    print("Compile check A-OK!")
