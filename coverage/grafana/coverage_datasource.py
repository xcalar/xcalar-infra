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

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from coverage.xce_func_test_coverage import XCEFuncTestCoverageData
from coverage.xd_unit_test_coverage import XDUnitTestCoverageData

cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO}})

from flask import Flask, request, jsonify, json, abort
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=cfg.get('LOG_LEVEL'),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

xce_coverage_data = XCEFuncTestCoverageData()
xd_coverage_data = XDUnitTestCoverageData()

mode_to_coverage_data = {
    'xce': xce_coverage_data,
    'xd': xd_coverage_data
    }

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
        return [s.replace('\.', '.').replace('\/', '/') for s in multi.strip('()').split('|')]
    return [multi.replace('\.', '.').replace('\/', '/')]

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

    names = []
    target = req.get('target', None)
    logger.info("target: {}".format(target))
    if not target:
        return jsonify(names) # XXXrs - exception?

    if target == 'xd_versions':
        names = xd_coverage_data.xd_versions()

    elif target == 'xce_versions':
        names = xce_coverage_data.xce_versions()

    elif target == 'xd_filegroups':
        names = xd_coverage_data.file_groups.group_names()
        names.append("All Files")

    elif target == 'xce_filegroups':
        names = xce_coverage_data.file_groups.group_names()
        names.append("All Files")

    # <xd_vers>:xdbuilds
    elif ':xdbuilds' in target:
        # Build list will be all builds available matching the XD version(s).
        xd_vers,foo = target.split(':')
        names = xd_coverage_data.builds(xd_versions=_parse_multi(xd_vers),
                                        reverse=True)

    # <build>:<fgroup>:xdfiles
    elif ':xdfiles' in target:
        # xdfiles list will be all files for which we track coverage (based on
        # files tracked for build).
        bnum1,fgroup,foo = target.split(':')
        names = xd_coverage_data.filenames(bnum=bnum1, group_name=fgroup)

    # <xce_vers>:xcebuilds
    elif ':xcebuilds' in target:
        # Build list will be all builds available matching the XCE version(s).
        xce_vers,foo = target.split(':')
        names = xce_coverage_data.builds(xce_versions=_parse_multi(xce_vers),
                                         reverse=True)
    # <build>:<fgroup>:xcefiles
    elif ':xcefiles' in target:
        # xcefiles list will be all files for which we track coverage (based on
        # files tracked for build).
        bnum1,fgroup,foo = target.split(':')
        names = xce_coverage_data.filenames(bnum=bnum1, group_name=fgroup)

    else:
        pass # XXXrs - exception?

    logger.debug("names: {}".format(names))
    return jsonify(names)

def _xd_results(*, xd_vers, first_bnum, names, ts):
    logger.info("xd_vers: {} first_bnum: {} names: {}"
                .format(xd_vers, first_bnum, names))
    builds = xd_coverage_data.builds(xd_versions=_parse_multi(xd_vers),
                                     first_bnum=first_bnum,
                                     reverse=False)

    results = []
    for bnum in builds:
        for name in names:
            for filename in xd_coverage_data.file_groups.expand(name=name):
                results.append({'target': '{}'.format(bnum),
                                'datapoints': [[xd_coverage_data.coverage(
                                                    bnum=bnum, filename=filename), ts]] })
    logger.debug("results: {}".format(results))
    return results

def _xce_results(*, xce_vers, first_bnum, names, ts):
    logger.info("xce_vers: {} first_bnum: {}".format(xce_vers, first_bnum))
    builds = xce_coverage_data.builds(xce_versions=_parse_multi(xce_vers),
                                      first_bnum=first_bnum,
                                      reverse=False)
    logger.info("builds: {}".format(builds))

    results = []
    for bnum in builds:
        for name in names:
            for filename in xce_coverage_data.file_groups.expand(name=name):
                results.append({'target': '{}'.format(bnum),
                                'datapoints': [[xce_coverage_data.coverage(
                                                    bnum=bnum, filename=filename), ts]] })
    logger.debug("results: {}".format(results))
    return results


def _comparison_table(*, target_name):
    """
    Target name specifes query.
    Format:
        <xce|xd>:<build_num_1>:<build_num_2>:<file_group>
    """
    try:
        mode,bnum1,bnum2,filenames = target_name.split(':')
    except Exception as e:
        abort(404, Exception('incomprehensible target_name: {}'.format(target_name)))

    coverage_data = mode_to_coverage_data.get(mode, None)
    if not coverage_data:
        err = 'unknown mode: {}'.format(mode)
        logger.exception(err)
        abort(404, ValueError(err))

    logger.info("mode {} bnum1 {} bnum2 {} filenames {}"
                .format(mode, bnum1, bnum2, filenames))

    rows = []
    columns = [
        {"text":"File", "type":"string"},
        {"text":"Build {} coverage pct.".format(bnum1), "type":"number"},
        {"text":"Build {} coverage pct.".format(bnum2), "type":"number"},
        {"text":"Delta", "type":"number"},
    ]

    for filename in _parse_multi(filenames):
        cvg1 = coverage_data.coverage(bnum=bnum1, filename=filename)
        cvg2 = coverage_data.coverage(bnum=bnum2, filename=filename)
        if cvg1 is None or cvg2 is None:
            delta = "NaN"
        else:
            delta = cvg2-cvg1
        rows.append([filename, cvg1, cvg2, delta])

    results = [{"columns": columns,
                "rows": rows,
                "type" : "table"}]

    return results


def _timeserie_results(*, target, request_ts_ms):
    """
    Target name format:
        <xce|xd>:<versions>:<first_bnum>:<names>
    """

    logger.info("start")

    t_name = target.get('target', None)
    logger.info("t_name: {}".format(t_name))
    if not t_name:
        err = 'target has no name: {}'.format(target)
        logger.exception(err)
        abort(404, ValueError(err))
    try:
        mode,vers,first_bnum,names = t_name.split(':')
    except Exception as e:
        err = 'incomprehensible target name: {}'.format(t_name)
        logger.exception(err)
        abort(404, ValueError(err))

    """
    first_bnum is the first build to return.
    Want all builds of same version since then.
    """
    if mode == "xd":
        return _xd_results(xd_vers = vers,
                           first_bnum = first_bnum,
                           names = _parse_multi(names),
                           ts = request_ts_ms)
    elif mode == "xce":
        return _xce_results(xce_vers = vers,
                            first_bnum = first_bnum,
                            names = _parse_multi(names),
                            ts = request_ts_ms)

    err = 'unknown mode: {}'.format(mode)
    logger.exception(err)
    abort(404, ValueError(err))


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

    # XXXrs - mostly boilerplate of little value...
    t_range = req.get('range', None)
    if not t_range:
        abort(404, Exception('range missing'))

    # XXXrs - ...except this. Use this time force all results into the present.
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
        if not request_type:
            request_type = target.get('type', 'timeserie')

        if request_type == 'table':
            target_name = target.get('target', None)
            logger.debug("target name: {}".format(target_name))
            # Table target name contains enough meta-data to produce the entire
            # comparison table.  We're done in one.
            results = _comparison_table(target_name=target_name)
            logger.debug("table results: {}".format(results))
            return jsonify(results)

        # Return results in timeserie format, but we're not actually
        # using a time-series.  We force all results into the board's
        # present time-frame so that nothing is filtered out.
        ts_results = _timeserie_results(target = target,
                                        request_ts_ms = from_ts_ms)
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
    app.run(host='0.0.0.0', port=3002, debug= True)
