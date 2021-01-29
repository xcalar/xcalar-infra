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
import math
import os
import random
import re
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from coverage.file_groups import FileGroups
from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.jenkins_aggregators import JenkinsJobDataCollection
from py_common.jenkins_aggregators import JenkinsJobMetaCollection
from py_common.mongo import MongoDB, JenkinsMongoDB

class XDUnitTestCoverage(object):
    GZIPPED = re.compile(r".*\.gz\Z")

    def __init__(self, *, path):
        self.logger = logging.getLogger(__name__)
        self.coverage_data = self._load_json(path=path)
        self.url_to_coverage = {}
        self.total_total_len = 0
        self.total_covered_len = 0
        for item in self.coverage_data:
            url = item['url']
            self.logger.debug("url: {}".format(url))
            totalLen = len(item['text'])
            self.total_total_len += totalLen
            self.logger.debug("total length: {}".format(totalLen))
            coveredLen = 0
            for cvrd in item['ranges']:
                coveredLen += (int(cvrd['end']) - int(cvrd['start']) - 1)
            self.total_covered_len += coveredLen
            self.logger.debug("covered length: {}".format(coveredLen))
            coveredPct = 100*coveredLen/totalLen
            self.logger.debug("covered pct: {}".format(coveredPct))
            self.url_to_coverage[url] = {'total_len': totalLen,
                                         'covered_len': coveredLen,
                                         'covered_pct': coveredPct}
        total_pct = 0
        if self.total_total_len:
            total_pct = 100*self.total_covered_len/self.total_total_len
        self.url_to_coverage['Total'] = {'total_len': self.total_total_len,
                                         'covered_len': self.total_covered_len,
                                         'covered_pct': total_pct}

    def _load_json(self, *, path):
        if not os.path.exists(path):
            # Try gzipped form
            zpath = "{}.gz".format(path)
            if not os.path.exists(zpath):
                err = "neither {} nor {} exist".format(path, zpath)
                self.logger.error(err)
                raise FileNotFoundError(err)
            path = zpath

        if self.GZIPPED.match(path):
            with gzip.open(path, "rb") as fh:
                return json.loads(fh.read().decode("utf-8"))
        with open(path, "r") as fh:
            return json.load(fh)

    def get_data(self):
        return self.url_to_coverage

    def total_coverage_pct(self):
        if not self.total_total_len:
            return 0
        return 100*self.total_covered_len/self.total_total_len


class XDUnitTestCoverageAggregator(JenkinsAggregatorBase):

    ENV_PARAMS = {"XD_UNIT_TEST_COVERAGE_FILE_NAME":
                        {"default": "coverage.json",
                         "required": True},
                  "XD_UNIT_TEST_ARTIFACTS_ROOT":
                        {"default": "/netstore/qa/coverage/XDUnitTest",
                         "required":True} }

    def __init__(self, *, job_name):
        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(XDUnitTestCoverageAggregator.ENV_PARAMS)
        self.coverage_file_name = cfg.get("XD_UNIT_TEST_COVERAGE_FILE_NAME")
        self.artifacts_root = cfg.get("XD_UNIT_TEST_ARTIFACTS_ROOT")
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__)

    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Return coverage info for a specific build.
        """
        try:
            bnum = jbi.build_number
            path = os.path.join(self.artifacts_root, bnum, self.coverage_file_name)
            self.logger.debug("path: {}".format(path))
            xdutc = XDUnitTestCoverage(path=path)
            data = {}
            for url,coverage in xdutc.get_data().items():
                self.logger.debug("url: {} coverage: {}".format(url, coverage))
                data[MongoDB.encode_key(url)] = coverage
            return {'coverage': data}
        except FileNotFoundError as e:
            self.logger.error("{} not found".format(path))
            return None


class XDUnitTestCoverageData(object):

    ENV_PARAMS = {"XD_UNIT_TEST_JOB_NAME": {"default": "XDUnitTest"}}

    # XXXrs - temporary static config.
    FILE_GROUPS = {"Critical Files": [
       "/ts/components/workbook/workbookManager.js"
       "/ts/components/dag/DagGraph.js",
       "/ts/components/dag/DagGraphExecutor.js",
       "/ts/components/dag/DagLineage.js",
       "/ts/components/dag/DagList.js",
       "/ts/components/dag/DagNodeExecutor.js",
       "/ts/components/dag/DagNodeMenu.js",
       "/ts/components/dag/DagQueryConverter.js",
       "/ts/components/dag/DagSubGraph.js",
       "/ts/components/dag/DagTab.js",
       "/ts/components/dag/DagTabManager.js",
       "/ts/components/dag/DagTabUser.js",
       "/ts/components/dag/DagTable.js",
       "/ts/components/dag/DagView.js",
       "/ts/components/dag/DagViewManager.js",
       "/ts/components/dag/node/DagNode.js",
       "/ts/components/worksheet/oppanel/SQLOpPanel.js"
       "/ts/components/sql/SQLDagExecutor.js",
       "/ts/components/sql/SQLEditor.js",
       "/ts/components/sql/SQLExecutor.js",
       "/ts/components/sql/SQLSnippet.js",
       "/ts/components/sql/sqlQueryHistory.js",
       "/ts/components/sql/workspace/SQLEditorSpace.js",
       "/ts/components/sql/workspace/SQLResultSpace.js",
       "/ts/components/sql/workspace/SQLTable.js",
       "/ts/components/sql/workspace/SQLTableLister.js",
       "/ts/components/sql/workspace/SQLTableSchema.js",
       "/ts/components/sql/workspace/SQLWorkSpace.js" ]}

    def __init__(self):

        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(XDUnitTestCoverageData.ENV_PARAMS)
        job_name = cfg.get("XD_UNIT_TEST_JOB_NAME")

        # XXXrs - This should NOT communicate directly with the DB, but
        #         should go through a REST client.
        jmdb = JenkinsMongoDB()
        self.data = JenkinsJobDataCollection(job_name=job_name, jmdb=jmdb)
        self.meta = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)

        # XXXrs - TEMPORARY (!?!) initialize every time with static configuration.
        #         Eventually, this configuration should be managed elsewhere.

        self.file_groups = FileGroups(meta=self.meta.coll)
        self.file_groups.reset()
        for name, files in XDUnitTestCoverageData.FILE_GROUPS.items():
            self.file_groups.append_group(name=name, files=files)

        self.file_groups.reset()
        for name, files in XDUnitTestCoverageData.FILE_GROUPS.items():
            self.file_groups.append_group(name=name, files=files)

    def xd_versions(self):
        """
        Return available XD versions for which we have data.
        XXXrs - version/branch :|
        """
        return self.meta.branches(repo='XD')

    def _get_coverage_data(self, *, bnum):
        data = self.data.get_data(bnum=bnum)
        if not data:
            return None
        return data.get('coverage', None)

    def builds(self, *, xd_versions=None,
                        first_bnum=None,
                        last_bnum=None,
                        reverse=False):

        rtn = []
        for bnum in self.meta.find_builds(repo='XD',
                                          branches=xd_versions,
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
            do_sort = True
            rawnames = sorted(coverage.keys())

        have_total = False
        # Reduce a URL to just a filename
        filenames = []
        for key in rawnames:
            url = MongoDB.decode_key(key)
            if url == 'Total':
                have_total = True
                continue
            fields = url.split('/')
            if len(fields) < 2:
                raise Exception("Incomprehensible: {}".format(url))
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
        coverage = self._get_coverage_data(bnum=bnum)
        if not coverage:
            return None
        for key,data in coverage.items():
            url = MongoDB.decode_key(key)
            if filename.lower() in url.lower():
                return coverage[key].get('covered_pct', None)
        return None


if __name__ == '__main__':
    """
    Useful little utility to emit csv coverage for critical files from given build.
    """

    cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.ERROR}})
    logging.basicConfig(level=cfg.get("LOG_LEVEL"),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])

    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--bnum", help="build number", required=True)
    args = parser.parse_args()

    data = XDUnitTestCoverageData()
    for fname in data.filenames(bnum=args.bnum, group_name="Critical Files"):
        coverage = data.coverage(bnum=args.bnum, filename=fname)
        if coverage is not None:
            print("{0}: {1:.2f}".format(fname, data.coverage(bnum=args.bnum, filename=fname)))
        else:
            print("{0}: None".format(fname))
