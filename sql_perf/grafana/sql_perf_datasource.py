#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import datetime
import logging
import os
import pytz
import random
import re
import statistics
import sys
import time

sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.INFO},
                        "SQL_SCALE_JOB_NAME": {"default": "SqlScaleTest"},
                        "PRECHECKIN_VERIFY_JOB_NAME": {"default": "BuildSqldfTestAggreagate"}})
from sql_perf import SqlPerfResults, SqlPerfResultsData
from sql_perf.comparison_pdf import SqlPerfComparisonPdf

from flask import Flask, request, jsonify, json, abort
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=cfg.get("LOG_LEVEL"),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

source_to_results = {
    'sql-scale': SqlPerfResultsData(job_name=cfg.get("SQL_SCALE_JOB_NAME")),
    'precheckin-verify': SqlPerfResultsData(job_name=cfg.get("PRECHECKIN_VERIFY_JOB_NAME"))}

sql_perf_pdf = SqlPerfComparisonPdf()

app = Flask(__name__)

cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'

methods = ('GET', 'POST')

@app.route('/', methods=methods)
@cross_origin()
def test_connection():
    """
    / should return 200 ok. Used for "Test connection" on the datasource config page.
    """
    return "Connection check A-OK!"

def _parse_multi(multi):
    if '|' in multi:
        return [s.replace('\.', '.') for s in multi.strip('()').split('|')]
    return [multi.replace('\.', '.')]

@app.route('/search', methods=methods)
@cross_origin()
def find_metrics():
    """
    /search used by the find metric options on the query tab in panels and variables.
    """
    logger.info("start")
    req = request.get_json()
    logger.info("request: {}".format(request))
    logger.info("payload: {}".format(req))

    values = []
    target = req.get('target', None)
    logger.info("target: {}".format(target))
    if not target:
        return jsonify(values) # XXXrs - exception?

    if target == 'source':
        values = list(source_to_results.keys())

    # <source>:test_group
    elif ':test_group' in target:
        source,rest = target.split(':')
        results_data = source_to_results[source]
        values = results_data.test_groups()

    # <source>:<test_group>:xce_versions
    if 'xce_versions' in target:
        source,tgroup,rest = target.split(':')
        results_data = source_to_results[source]
        values = results_data.xce_versions(test_group=tgroup)

    # <source>:<test_group>:<xce_vers>:build1
    elif ':build1' in target:
        # Build1 list will be all builds available matching the Xcalar version(s).
        # Once selected, the remaining metrics will be queried in context of the
        # selected build (comparable builds will have matching test type).
        source,tgroup,xce_vers,rest = target.split(':')
        results_data = source_to_results[source]
        xce_versions = _parse_multi(xce_vers)
        logger.info("finding builds for tgroup {} xce_versions {}"
                    .format(tgroup, xce_versions))
        values = results_data.find_builds(test_group=tgroup,
                                          xce_versions=_parse_multi(xce_vers),
                                          reverse=True)

    # <source>:<test_group>:<xce_vers>:<bnum1>:build2
    elif ':build2' in target:
        # Build2 list will be all builds available matching the Xcalar version(s)
        # and of same test type as build1 (suitable for comparison).
        source,tgroup,xce_vers,bnum1,rest = target.split(':')
        results_data = source_to_results[source]
        test_type = results_data.test_type(test_group=tgroup, bnum=bnum1)
        # Only display choices where test type (hash of test parameters)
        # is the same as the "base" build (since otherwise comparison is misleading).
        values = results_data.find_builds(test_group=tgroup,
                                          test_type=test_type,
                                          xce_versions=_parse_multi(xce_vers),
                                          reverse=True)
    # <source>:<test_group>:<bnum1>:query
    elif ':query' in target:
        # Return list of all supported query names (as determined by selected build1).
        source,tgroup,bnum1,rest = target.split(':')
        results_data = source_to_results[source]
        values = results_data.query_names(test_group=tgroup, bnum=bnum1)

    # metric
    elif 'metric' in target:
        values = SqlPerfResults.metric_names()

    else:
        pass # XXXrs - exception?

    logger.debug("values: {}".format(values))
    return jsonify(values)

def _config_table(*, target_name):
    """
    Target name specifes query.
    Format:
        <source>:<test_group>:<bnum>:configparams
    """
    try:
        source,tgroup,bnum,rest = target_name.split(':')
    except Exception as e:
        abort(404, Exception('incomprehensible target_name: {}'.format(target_name)))

    results_data = source_to_results[source]
    config_params = results_data.config_params(test_group=tgroup, bnum=bnum)
    columns = [
        {"text":"Number of Users", "type":"string"},
        {"text":"Notes", "type":"string"},
        {"text":"Data Source", "type":"string"}
    ]
    rows = [[config_params.get('num_users', 'Unknown'),
             config_params.get('notes', 'Unknown'),
             config_params.get('data_source', 'Unknown')]]
    results = [{"columns": columns,
                "rows": rows,
                "type" : "table"}]

    return results

def _results_table(*, target_name):
    """
    Target name specifes query.
    Format:
        <source>:<test_group>:<build_num_1>:<build_num_2>:<metric_name>
    """

    try:
        source,tgroup,bnum1,bnum2,mname = target_name.split(':')
    except Exception as e:
        abort(404, Exception('incomprehensible target_name: {}'.format(target_name)))

    logger.info("tgroup {} bnum1 {} bnum2 {} mname {}"
                .format(tgroup, bnum1, bnum2, mname))

    # Spin up a comparison pdf file for the comparison of interest.
    try:
        sql_perf_pdf.compare(test_group=tgroup, bnum1=bnum1, bnum2=bnum2)
    except Exception as e:
        logger.exception("failed to generate pdf comparison tgroup: {} bnum1: {} bnum2: {}"
                         .format(tgroup, bnum1, bnum2))

    rows = []
    columns = [
        {"text":"Query", "type":"string"},
        {"text":"Build {} mean {}".format(bnum1, mname), "type":"number"},
        {"text":"Build {} mean {}".format(bnum2, mname), "type":"number"},
        {"text":"Delta", "type":"number"},
        {"text":"Delta %", "type":"number"}
    ]

    # Query names are a component of test_type, so all tests of matching
    # type will have identical sets of query names.
    results_data = source_to_results[source]
    for qname in results_data.query_names(test_group=tgroup, bnum=bnum1):
        # Grafana doesn't aggregate into tables, so we have to roll our own...
        b1vals = results_data.query_vals(test_group=tgroup, bnum=bnum1,
                                         qname=qname, mname=mname)
        b1mean = statistics.mean(b1vals)

        b2vals = results_data.query_vals(test_group=tgroup, bnum=bnum2,
                                         qname=qname, mname=mname)
        b2mean = statistics.mean(b2vals)

        delta_pct = 0
        if b1mean:
            delta_pct = 100*(b2mean-b1mean)/b1mean

        rows.append([qname, b1mean, b2mean, b2mean-b1mean, delta_pct])

    results = [{"columns": columns,
                "rows": rows,
                "type" : "table"}]

    return results


def _get_datapoints(*, source, tgroup, bnum, qname, mname, request_ts_ms=None):
        logger.debug("start")
        results_data = source_to_results[source]
        try:
            data = results_data.results(test_group=tgroup, bnum=bnum)
        except Exception as e:
            logger.exception("failed to load data")
            abort(404, Exception('failed to load data'))
        if request_ts_ms:
            ts_ms = request_ts_ms
        else:
            ts_ms = data['start_ts_ms']
        logger.debug("get values")
        qvals = results_data.query_vals(test_group=tgroup, bnum=bnum,
                                        qname=qname, mname=mname)
        logger.debug("qvals: {}".format(qvals))
        return [[qv,ts_ms] for qv in qvals]


def _timeserie_results(*, target, request_ts_ms):
    """
    Target name specifies query.
    Format:
        <source>:<test_group>:<xce_versions>:<build_num>:<query_names>:<metric_name>:<mode>
    """

    logger.info("start")

    target_name = target.get('target', None)
    logger.info("target_name: {}".format(target_name))
    if not target_name:
        err = 'target has no name: {}'.format(target)
        logger.exception(err)
        abort(404, ValueError(err))
    try:
        source,tgroup,xver,bnum,qname,mname,mode = target_name.split(':')
    except Exception as e:
        err = 'incomprehensible target name: {}'.format(target_name)
        logger.exception(err)
        abort(404, ValueError(err))

    if mode != 'multibuild' and mode != 'onebuild':
        err = 'invalid mode: {}'.format(mode)
        logger.exception(err)
        abort(404, ValueError(err))

    if mode == 'onebuild':
        """
        only want results from build indicated by bnum
        xce_versions is ignored
        """
        data = _get_datapoints(source=source, tgroup=tgroup,
                               bnum=bnum, qname=qname, mname=mname,
                               request_ts_ms=request_ts_ms)
        if not data:
            return []
        return [ {'target': "{}.{}".format(qname,bnum),
                  'datapoints': data} ]

    """
    mode is 'multibuild'
    bnum is the first build to return.  Want all builds of matching type since then.
    qname is allowed to be multi e.g. "(q1|q2|q3...)"
    """
    results = []
    results_data = source_to_results[source]
    test_type = results_data.test_type(test_group=tgroup, bnum=bnum)
    builds = results_data.find_builds(test_group=tgroup,
                                      first_bnum=bnum,
                                      xce_versions=_parse_multi(xver),
                                      test_type=test_type)

    qnames = _parse_multi(qname)
    for bnum in builds:
        for qname in qnames:
            data = _get_datapoints(source=source, tgroup=tgroup,
                                   bnum=bnum, qname=qname, mname=mname,
                                   request_ts_ms=request_ts_ms)
            if not data:
                continue
            results.append({'target': "{}".format(bnum),
                            'datapoints': data})
    logger.debug("results: {}".format(results))
    return results


def _zulu_time_to_ts_ms(t_str):
    dt = datetime.datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%S.%fZ")
    return int(dt.replace(tzinfo=pytz.utc).timestamp()*1000)


@app.route('/query', methods=methods)
@cross_origin(max_age=600)
def query_metrics():
    """
    /query should return metrics based on input.
    """
    logger.info("start")
    req = request.get_json()
    logger.info("request: {}".format(req))
    logger.info("request.args: {}".format(request.args))

    t_range = req.get('range', None)
    if not t_range:
        abort(404, Exception('range missing'))

    iso_from = t_range.get('from', None)
    if not iso_from:
        abort(404, Exception('range[from] missing'))
    from_ts_ms = _zulu_time_to_ts_ms(iso_from)
    logger.info("timestamp_from: {}".format(from_ts_ms))

    iso_to = t_range.get('to', None)
    if not iso_to:
        abort(404, Exception('range[to] missing'))
    to_ts_ms = _zulu_time_to_ts_ms(iso_to)
    logger.info("timestamp_to: {}".format(to_ts_ms))

    freq_ms = req.get('intervalMs', None)
    if not freq_ms:
        abort(404, Exception('intervalMs missing'))
    logger.info("freq_ms: {}".format(freq_ms))

    results = []
    request_type = None
    for target in req['targets']:
        if request_type and request_type != target.get('type', 'timeserie'):
            abort(404, Exception('invalid mixed request types'))
        if not request_type:
            request_type = target.get('type', 'timeserie')
        if request_type == 'table':
            target_name = target.get('target', None)
            logger.debug("target name: {}".format(target_name))
            if "configparams" in target_name:
                results = _config_table(target_name=target_name)
            else:
                # Table target name contains enough meta-data to produce the entire
                # comparison table.  We're done in one.
                results = _results_table(target_name=target_name)
            logger.debug("table results: {}".format(results))
            return jsonify(results)

        # Return results in timeserie format, but we're not actually
        # using a time-series.  We force all results into the board's
        # present time-frame so that nothing is filtered out.
        ts_results = _timeserie_results(target = target,
                                        request_ts_ms = from_ts_ms)
                                        #from_ts_ms = from_ts_ms,
                                        #to_ts_ms = to_ts_ms)
        results.extend(ts_results)

    logger.debug("timeserie results: {}".format(results))
    return jsonify(results)


@app.route('/annotations', methods=methods)
@cross_origin(max_age=600)
def query_annotations():
    """
    /annotations should return annotations. :p
    """
    req = request.get_json()
    logger.info("headers: {}".format(request.headers))
    logger.info("req: {}".format(req))
    abort(404, Exception('not supported'))


@app.route('/panels', methods=methods)
@cross_origin()
def get_panel():
    """
    No documentation for /panels ?!?
    """
    req = request.args
    logger.info("headers: {}".format(request.headers))
    logger.info("req: {}".format(req))
    abort(404, Exception('not supported'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001, debug= True)
