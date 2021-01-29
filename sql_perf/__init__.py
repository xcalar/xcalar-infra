#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

__all__=[]

from datetime import datetime
import hashlib
import json
import logging
import os
import pytz
import re
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.jenkins_aggregators import JenkinsJobDataCollection
from py_common.jenkins_aggregators import JenkinsJobMetaCollection
from py_common.mongo import MongoDB, JenkinsMongoDB
from py_common.sorts import nat_sort

class SqlPerfIter(object):
    """
    Class representing a single test iteration file.
    """
    version_pat = re.compile(r".*\(version=\'xcalar-(.*?)-.*")

    def _utc_to_ts_ms(self, t_str):
        dt = datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%S.%f")
        return int(dt.replace(tzinfo=pytz.utc).timestamp()*1000)

    def __init__(self, *, bnum, inum, path):
        """
        Initializer

        Required parameters:
            bnum:   Build number
            inum:   Iteration number
            path:   Path to iteration .json file
        """

        self.logger = logging.getLogger(__name__)

        self.bnum = bnum
        self.inum = inum
        self.dataByQ = {}
        with open(path, 'r') as fh:
            self.data = json.load(fh)

        self.test_group = self.data.get('group', None)
        if not self.test_group:
            raise ValueError("no test group in data")

        threads = self.data.get('threads', None)
        if not threads:
            raise ValueError("no threads in data")

        self.num_users = len(threads)
        self.notes = self.data.get('notes', None)
        if not self.notes:
            raise ValueError("no notes in data")

        ds = self.data.get('dataSource', None)
        if ds:
            ds = ds.get('dataSource', None)
        if not ds:
            raise ValueError("no dataSource in data")
        self.data_source = os.path.basename(os.path.abspath(ds))

        for tnum, queryStats in self.data['threads'].items():
            self.logger.debug("tnum: {}, queryStats: {}".format(tnum, queryStats))
            for q in queryStats:
                self.logger.debug("q: {}".format(q))
                if isinstance(q, list):
                    self.dataByQ.setdefault(q[0]['qname'], []).append(q[0])
                else:
                    self.dataByQ.setdefault(q['qname'], []).append(q)

        self.start_ts_ms = self._utc_to_ts_ms(self.data['startUTC'])
        self.end_ts_ms = self._utc_to_ts_ms(self.data['endUTC'])

        # Test type is an md5 hash of test parameters for easy identification
        # of like tests which can be sanely compared.
        hashstr = "{}{}{}{}{}".format(self.test_group, self.num_users,
                                      self.notes, self.data_source,
                                      ":".join(self.query_names()))
        self.test_type = hashlib.md5(hashstr.encode()).hexdigest()

    def query_names(self):
        """
        Return sorted list of available query names (e.g. "q3")
        """
        return sorted(self.dataByQ.keys(), key=nat_sort)

    def _results_for_query(self, *, qname):
        """
        Get all results for named query.

        Parameters:
            qname:  Query name (e.g. "q11")

        Returns:
            List of dictionaries of the form:
                {'exe': <query exe time>,
                 'fetch': <query fetch time>}
        """
        results = []
        for q in self.dataByQ.get(qname, []):
            if 'xcalar' in q:
                qstart = q['xcalar']['queryStart']
                qend = q['xcalar']['queryEnd']
                fstart = q['xcalar']['fetchStart']
                fend = q['xcalar']['fetchEnd']
            else:
                qstart = q['qStart']
                qend = q['qEnd']
                fstart = q['fStart']
                fend = q['fEnd']
            results.append({'exe': qend-qstart,
                            'fetch': fend-fstart})
        return results

    def query_vals(self):
        """
        Get all result values for all queries:
            <query>:[{'exe':<val>, 'fetch':<val>}, ...],
            <query>:...

        """
        results = {}
        for qname in self.query_names():
            results[qname] = self._results_for_query(qname=qname)
        return results

    @staticmethod
    def csv_headers():
        return "Build,TestGroup,Query,Iteration,StartTsMs,EndTsMs,XcalarQueryTime,XcalarFetchTime"

    def to_csv(self):
        """
        Return list of csv strings of iteration data.
        """
        lines = []
        for qname in self.query_names():
            for results in self._results_for_query(qname=qname):
                lines.append("{},{},{},{},{},{},{}"
                             .format(self.bnum,
                                     self.test_group,
                                     qname,
                                     self.inum,
                                     self.start_ts_ms,
                                     self.end_ts_ms,
                                     results['exe'],
                                     results['fetch']))
        return lines

    def to_json(self):
        """
        Return "canonical" json format string.
        """
        raise Exception("Not implemented.")


class SqlPerfNoResultsError(Exception):
    pass


class SqlPerfResults(object):
    """
    Class representing the collection of all test iterations associated
    with a particular build.
    """

    def __init__(self, *, bnum, dir_path, file_pats):
        """
        Initializer

        Required parameters:
            bnum:       Build number
            dir_path:   Path to directory containing all iteration files.
        """
        self.logger = logging.getLogger(__name__)
        self.build_num = bnum
        self.logger.info("start bnum {} dir_path {}".format(bnum, dir_path))
        self.iters_by_group = {}
        self.file_pats = file_pats

        if not os.path.exists(dir_path):
            raise SqlPerfNoResultsError("directory does not exist: {}".format(dir_path))

        # Load each of the iteration files...
        for name in os.listdir(dir_path):
            path = os.path.join(dir_path, name)
            self.logger.info("path: {}".format(path))
            m = None
            for pat in self.file_pats:
                m = pat.match(name)
                if not m:
                    self.logger.info("skipping: {}".format(path))
                    continue
                break
            else:
                continue

            try:
                inum = m.group(1) # N.B.: First match group expected to be iteration number
            except IndexError:
                self.logger.info("no iteration number, using 0")
                inum = "0"

            try:
                spi = SqlPerfIter(bnum=bnum, inum=inum, path=path)
                self.iters_by_group.setdefault(spi.test_group, {})[inum] = spi
            except Exception as e:
                self.logger.exception("error loading {}".format(path))
                continue

        if not self.iters_by_group.keys():
            raise SqlPerfNoResultsError("no results found: {}".format(dir_path))

    def test_groups(self):
        #return self.iters_by_group.keys()
        return ['tpchTest', 'tpcdsTest']

    def to_csv(self):
        """
        Return "canonical" csv format string.

            Build,TestGroup,StartTsMs,EndTsMs,Query,XcalarQueryTimeMs,XcalarFetchTimeMs
            456,tpchTest,1561496761798,1561496764172,q6,34857,2702
            457,tpchTest,1561496788738,1561496799737,q6,32190,2113
            ...
        """
        csv = [SqlPerfIter.csv_headers()]
        for tg, iters in self.iters_by_group.items():
            for i,obj in iters.items():
                csv.extend(obj.to_csv())
        return "\n".join(csv)

    def to_json(self):
        """
        Return "canonical" json format string.
        """
        raise Exception("Not implemented.")

    def query_names(self, *, test_group):
        """
        Return sorted list of available query names (e.g. "q3")
        """
        iters = self.iters_by_group.get(test_group, None)
        if not iters:
            return None
        names = None
        for i,obj in iters.items():
            if not names:
                names = obj.query_names()
                continue

            # All iterations are presumed to run the same set of
            # queries.  Validate this assumption!

            check_names = obj.query_names()
            if check_names != names:
                raise Exception("iteration {} query names {} don't match master set: {}"
                                .format(i, check_names, names))
        return names

    @staticmethod
    def metric_names():
        """
        Return list of available metric names.
        """
        return ['total', 'exe', 'fetch']

    def query_vals(self, *, test_group):

        iters = self.iters_by_group.get(test_group, None)
        if not iters:
            return None
        results = {}
        for i,obj in iters.items():
            for q,l in obj.query_vals().items():
                results.setdefault(q, []).extend(l)
        return results

    def index_data(self):
        data = {}
        for tg in self.test_groups():
            iters = self.iters_by_group.get(tg, None)
            if not iters:
                continue

            iter_nums = sorted(iters.keys(), key=nat_sort)

            data[tg] = {'start_ts_ms': iters[iter_nums[0]].start_ts_ms,
                        'end_ts_ms': iters[iter_nums[-1]].end_ts_ms,
                        # Assume the configuration is the same for all iterations...
                        'test_type': iters[iter_nums[0]].test_type,
                        'num_users': iters[iter_nums[0]].num_users,
                        'notes': iters[iter_nums[0]].notes,
                        'data_source': iters[iter_nums[0]].data_source,
                        'query_vals': self.query_vals(test_group = tg)}
        return data

class SqlPerfResultsAggregator(JenkinsAggregatorBase):

    ENV_PARAMS = {"SQL_PERF_ARTIFACTS_ROOT": {"default": "/netstore/qa/jenkins"}}

    def __init__(self, *, job_name, file_pats):

        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(SqlPerfResultsAggregator.ENV_PARAMS)
        self.artifacts_root = cfg.get('SQL_PERF_ARTIFACTS_ROOT')
        self.file_pats = file_pats
        super().__init__(job_name=job_name,
                         agg_name=self.__class__.__name__)

    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        job_name = jbi.job_name
        bnum = jbi.build_number
        try:
            dir_path=os.path.join(self.artifacts_root, job_name, bnum)
            results = SqlPerfResults(bnum=bnum, dir_path=dir_path, file_pats=self.file_pats)
        except SqlPerfNoResultsError as e:
            return None
        data = results.index_data()

        atms = []
        tpch = False
        tpcds = False
        if 'tpchTest' in data:
            tpch = True
            atms.append(('tpchTest_builds', bnum))
            atms.append(('test_groups', 'tpchTest'))
        if 'tpcdsTest' in data:
            tpcds = True
            atms.append(('tpcdsTest_builds', bnum))
            atms.append(('test_groups', 'tpcdsTest'))

        xce_branch = jbi.git_branches().get('XCE', None)
        if xce_branch:
            data['xce_version'] = xce_branch
            builds_key_sfx = MongoDB.encode_key("XCE_{}_builds".format(xce_branch))
            if tpch:
                atms.append(('tpchTest_XCE_branches', xce_branch))
                atms.append(('tpchTest_{}'.format(builds_key_sfx), bnum))
            if tpcds:
                atms.append(('tpcdsTest_XCE_branches', xce_branch))
                atms.append(('tpcdsTest_{}'.format(builds_key_sfx), bnum))
        if atms:
            data['_add_to_meta_set'] = atms
        return data


class SSTResultsAggregator(SqlPerfResultsAggregator):

     # N.B.: First match group expected to be iteration number
     file_pats = [re.compile(r".*-(\d+)_tpc(.*)Test\.json\Z"),
                  re.compile(r".*-(\d+)-xcalar_tpc.*Test\.json\Z")]

     def __init__(self, *, job_name):
         super().__init__(job_name=job_name, file_pats=SSTResultsAggregator.file_pats)

class BSTAResultsAggregator(SqlPerfResultsAggregator):

     file_pats = [re.compile(r"\Aprecheckin_verify_tpchTest.json\Z")]

     def __init__(self, *, job_name):
         super().__init__(job_name=job_name, file_pats=BSTAResultsAggregator.file_pats)


class SqlPerfResultsData(object):

    def __init__(self, *, job_name):
        """
        Initializer

        Environment parameters:
            SQL_PERF_JOB_NAME:  Jenkins job name.
        """
        self.logger = logging.getLogger(__name__)
        self.job_name = job_name
        jmdb = JenkinsMongoDB()
        self.data = JenkinsJobDataCollection(job_name=self.job_name, jmdb=jmdb)
        self.meta = JenkinsJobMetaCollection(job_name=self.job_name, jmdb=jmdb)
        self.results_cache = {}

    def test_groups(self):
        doc = self.meta.coll.find_one({'_id': 'test_groups'})
        if not doc:
            return None
        return doc.get('values')

    def xce_versions(self, *, test_group):
        """
        Return all Xcalar versions represented in the index.
        """
        key = "{}_XCE_branches".format(test_group)
        doc = self.meta.coll.find_one({'_id': key})
        return doc.get('values', None)

    def builds_for_version(self, *, test_group, xce_version):
        key = MongoDB.encode_key("{}_XCE_{}_builds".format(test_group, xce_version))
        doc = self.meta.coll.find_one({'_id': key})
        if not doc:
            return None
        return doc.get('values', None)

    def builds_for_type(self, *, test_group, test_type):
        builds = []
        pat = {'{}.test_type'.format(test_group):test_type}
        self.logger.info("XXX: pat: {}".format(pat))
        for doc in self.data.coll.find(pat, projection={'_id':1}):
            builds.append(doc['_id'])
        self.logger.info("XXX: builds: {}".format(builds))
        return builds

    def find_builds_old(self, *, test_group,
                             xce_versions=None,
                             first_bnum=None,
                             last_bnum=None,
                             test_type=None,
                             start_ts_ms=None,
                             end_ts_ms=None,
                             reverse=False):
        """
        Return list of build numbers matching the given attributes.
        By default, list is sorted in ascending natural number order.

        Required parameter:
            test_group:     the test group

        Optional parameters:
            xce_versions:   list of Xcalar versions
            first_bnum:     matching build number must be gte this value
            last_bnum:      matching build number must be lte this value
            test_type:      results for build must be of this test_type
            start_ts_ms:    matching build start time gte this value
            end_ts_ms:      matching build end time lte this value
            reverse:        if True, results will be sorted in decending order.
        """
        # XXXrs - FUTURE - Replace silly brute-force scan with proper query...
        self.logger.debug("start")
        found = []
        for bnum,data in self.data.get_data_by_build().items():

            self.logger.debug("processing bnum {}".format(bnum))

            if test_group not in data:
                self.logger.debug("test_group {} not in data".format(test_group))
                # no results
                continue

            xce_ver = data.get('xce_version', None)
            if xce_versions and (not xce_ver or xce_ver not in xce_versions):
                self.logger.debug("xce_version mismatch want {} build {} has {}"
                                  .format(xce_versions, bnum, xce_ver))
                continue

            tg_data = data[test_group]

            if test_type and tg_data['test_type'] != test_type:
                self.logger.debug("test_type mismatch want {} build {} has {}"
                                  .format(test_type, bnum, tg_data['test_type']))
                continue
            if start_ts_ms and tg_data['start_ts_ms'] < start_ts_ms:
                continue
            if end_ts_ms and tg_data['end_ts_ms'] > end_ts_ms:
                continue
            if first_bnum and int(bnum) < int(first_bnum):
                continue
            if last_bnum and int(bnum) > int(last_bnum):
                continue
            found.append(bnum)
        self.logger.info("returning: {}".format(found))
        return sorted(found, key=nat_sort, reverse=reverse)

    def find_builds(self, *, test_group,
                             xce_versions=None,
                             test_type=None,
                             first_bnum=None,
                             last_bnum=None,
                             reverse=False):
        """
        Return list of build numbers matching the given attributes.
        By default, list is sorted in ascending natural number order.

        Required parameter:
            test_group:     the test group

        Optional parameters:
            xce_versions:   list of Xcalar versions
            test_type:      results for build must be of this test_type
            first_bnum:     matching build number must be gte this value
            last_bnum:      matching build number must be lte this value
            reverse:        if True, results will be sorted in decending order.
        """

        self.logger.debug("start")
        found = set([])
        if xce_versions:
            for version in xce_versions:
                bfv = self.builds_for_version(test_group=test_group,
                                              xce_version=version)
                found = found.union(set(bfv))

        if test_type:
            self.logger.info("test_type: {}".format(test_type))
            for_type = self.builds_for_type(test_group=test_group, test_type=test_type)
            found = found.intersection(for_type)

        if not found:
            return []

        rtn = []
        if first_bnum or last_bnum:
            for bnum in found:
                if first_bnum and int(bnum) < int(first_bnum):
                    continue
                if last_bnum and int(bnum) > int(last_bnum):
                    continue
                rtn.append(bnum)
        else:
            rtn = found

        rtn = sorted(rtn, key=nat_sort, reverse=reverse)
        self.logger.info("returning: {}".format(rtn))
        return rtn

    def results(self, *, test_group, bnum):
        cache_key = '{}:{}'.format(test_group, bnum)
        if cache_key in self.results_cache:
            return self.results_cache[cache_key]
        doc = self.data.get_data(bnum=bnum)
        data = {}
        if doc:
            data = doc.get(test_group, {})
        self.results_cache[cache_key] = data
        return data

    def test_type(self, *, test_group, bnum):
        try:
            data = self.results(test_group=test_group, bnum=bnum)
            return data['test_type']
        except Exception as e:
            self.logger.exception("exception finding test type")
            return None

    def config_params(self, *, test_group, bnum):
        try:
            data = self.results(test_group=test_group, bnum=bnum)
            return {'test_group': data.get('test_group'),
                    'num_users': data.get('num_users'),
                    'notes': data.get('notes'),
                    'data_source': data.get('data_source')}
        except Exception as e:
            self.logger.exception("exception finding config params")
            return {}

    def query_names(self, *, test_group, bnum):
        try:
            data = self.results(test_group=test_group, bnum=bnum)
            query_vals = data['query_vals']
            return sorted(query_vals.keys(), key=nat_sort)
        except Exception as e:
            self.logger.exception("exception finding query names")
            return []

    def query_vals(self, *, test_group, bnum, qname, mname):
        try:
            data = self.results(test_group=test_group, bnum=bnum)
            if mname == 'total':
                return[v['exe']+v['fetch'] for v in data['query_vals'][qname]]
            return [v[mname] for v in data['query_vals'][qname]]
        except Exception as e:
            self.logger.exception("exception finding query values")
            return []


"""
# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")

    import time
    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    data = SqlPerfData()

    now_ms = datetime.now().timestamp()*1000
    week_ms = 7*24*60*60*1000
    last_week = data.find_builds(start_ts_ms=(now_ms-week_ms),
                                 end_ts_ms=now_ms)
    #logger.info("last week: {}".format([s.build_num for s in last_week]))
    logger.info("last week: {}".format(last_week))
    last_month = data.find_builds(start_ts_ms=(now_ms-(4*week_ms)),
                                  end_ts_ms=now_ms,
                                  reverse=True)
    #logger.info("last month: {}".format([s.build_num for s in last_month]))
    logger.info("last month: {}".format(last_month))

    for bnum in last_week:
        results = data.results(bnum = bnum)
        print(results)

"""

# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")

    from pprint import pformat
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--bnum", help="build number", required=True)
    args = parser.parse_args()

    dir_path = os.path.join("/netstore/qa/jenkins/SqlScaleTest", args.bnum)


    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    results = SqlPerfResults(bnum = args.bnum, dir_path = dir_path)
    data = results.index_data()
    #print(pformat(data))
    for query,vals in data['tpcdsTest']['query_vals'].items():
        print("{}: {}".format(query, vals))


    #print(pformat(results.index_data()))
