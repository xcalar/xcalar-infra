#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import gzip
import json
import logging
import os
import re
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from coverage.file_groups import FileGroups
from coverage.clang import ClangCoverageAggregator
from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.jenkins_aggregators import JenkinsJobDataCollection
from py_common.jenkins_aggregators import JenkinsJobMetaCollection
from py_common.mongo import MongoDB, JenkinsMongoDB
from py_common.sorts import nat_sort

class XCEFuncTestCoverageAggregator(ClangCoverageAggregator):

    ENV_PARAMS = {"XCE_FUNC_TEST_COVERAGE_FILE_NAME":
                        {"default": "coverage.json",
                         "required": True},
                  "XCE_FUNC_TEST_ARTIFACTS_ROOT":
                        {"default": "/netstore/qa/coverage/XCEFuncTest",
                         "required":True} }

    def __init__(self, *, job_name):
        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(XCEFuncTestCoverageAggregator.ENV_PARAMS)
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__,
                         coverage_file_name = cfg.get("XCE_FUNC_TEST_COVERAGE_FILE_NAME"),
                         artifacts_root = cfg.get("XCE_FUNC_TEST_ARTIFACTS_ROOT"))


class XCEFuncTestCoverageData(object):

    ENV_PARAMS = {"XCE_FUNC_TEST_JOB_NAME": {"default": "XCEFuncTest"}}

    # XXXrs - temporary static config.
    XCE_FUNC_TEST_FILE_GROUPS = \
            {"Critical Files": ["liboperators/GlobalOperators.cpp",
                                "liboperators/LocalOperators.cpp",
                                "liboperators/XcalarEval.cpp",
                                "liboptimizer/Optimizer.cpp",
                                "libxdb/Xdb.cpp",
                                "libruntime/Runtime.cpp",
                                "libquerymanager/QueryManager.cpp",
                                "libqueryeval/QueryEvaluate.cpp",
                                "libmsg/TwoPcFuncDefs.cpp"]}

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(XCEFuncTestCoverageData.ENV_PARAMS)
        job_name = cfg.get("XCE_FUNC_TEST_JOB_NAME")

        # XXXrs - This should NOT communicate directly with the DB, but
        #         should go through a REST client.
        jmdb = JenkinsMongoDB()
        self.data = JenkinsJobDataCollection(job_name=job_name, jmdb=jmdb)
        self.meta = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)

        # XXXrs - TEMPORARY (!?!) initialize every time with static configuration.
        #         Eventually, this configuration should be managed elsewhere.

        self.file_groups = FileGroups(meta=self.meta.coll)
        self.file_groups.reset()
        for name, files in XCEFuncTestCoverageData.XCE_FUNC_TEST_FILE_GROUPS.items():
            self.file_groups.append_group(name=name, files=files)

    def xce_versions(self):
        """
        Return available XCE versions for which we have data.
        XXXrs - version/branch :|
        """
        return self.meta.branches(repo='XCE')

    def _get_coverage_data(self, *, bnum):
        data = self.data.get_data(bnum=bnum)
        if not data:
            return None
        return data.get('coverage', None)

    def builds(self, *, xce_versions=None,
                        first_bnum=None,
                        last_bnum=None,
                        reverse=False):
        rtn = []
        for bnum in self.meta.find_builds(repo='XCE',
                                          branches=xce_versions,
                                          first_bnum=first_bnum,
                                          last_bnum=last_bnum,
                                          reverse=reverse):
            if self._get_coverage_data(bnum = bnum):
                # Only builds with coverage data please
                rtn.append(bnum)
        return rtn

    def filenames(self, *, bnum, group_name=None):
        coverage = self._get_coverage_data(bnum=bnum)
        if not coverage:
            return None

        rawnames = []
        do_sort = False
        if group_name is not None and group_name != "All Files":
            rawnames = self.file_groups.expand(name=group_name)
        else:
            # Load all file names available in coverage
            do_sort = True
            rawnames = coverage.keys()

        # Reduce to just final two path components
        filenames = []
        have_total = False
        for key in rawnames:
            name = MongoDB.decode_key(key)
            if name == 'totals':
                have_total = True
                continue
            fields = name.split('/')
            if len(fields) < 2:
                raise Exception("Incomprehensible: {}".format(name))
            filename = "{}/{}".format(fields[-2], fields[-1])
            if filename in filenames:
                raise Exception("Duplicate: {}".format(filename))
            filenames.append(filename)
        if do_sort:
            filenames.sort()
        if have_total:
            filenames.insert(0, "Total")
        return filenames

    def coverage(self, *, bnum, filename):
        """
        XXXrs - FUTURE - extend to return other than "lines" percentage.
        """
        if filename == "Total":
            filename = "totals"
        coverage = self._get_coverage_data(bnum=bnum)
        if not coverage:
            return None
        for key,data in coverage.items():
            name = MongoDB.decode_key(key)
            if filename in name:
                return coverage[key].get('lines', {}).get('percent', None)
        return None

if __name__ == '__main__':
    """
    Useful little utility to emit csv coverage for critical files from given build.
    """

    cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.ERROR}})
    logging.basicConfig(level=cfg.get("LOG_LEVEL"),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--bnum", help="build number", required=True)
    args = parser.parse_args()

    data = XCEFuncTestCoverageData()
    for fname in data.filenames(bnum=args.bnum, group_name="Critical Files"):
        coverage = data.coverage(bnum=args.bnum, filename=fname)
        if coverage is not None:
            print("{0}: {1:.2f}".format(fname, data.coverage(bnum=args.bnum, filename=fname)))
        else:
            print("{0}: None".format(fname))
