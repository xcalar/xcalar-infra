#!/usr/bin/env python3

# Copyright 2019-2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import copy
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
cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                        'JDQ_SERVICE_HOST': {'required': True},
                        'JDQ_SERVICE_PORT': {'required': True}})

from py_common.jenkins_data_query.client import JDQClient
jdq_client = JDQClient(host = cfg.get('JDQ_SERVICE_HOST'),
                       port = cfg.get('JDQ_SERVICE_PORT'))

from flask import Flask, request, jsonify, json, abort
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=cfg.get("LOG_LEVEL"),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

app = Flask(__name__)

cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'

methods = ('GET', 'POST')

# Table Modes
JOBS_STATS = 'All Jobs Stats'
TOTAL_BUILDS = 'Total Builds Trends'
PASS_PCT = 'Pass Pct. Trends'
PASS_DUR = 'Pass Duration Trends'
DOWNSTREAM = 'Downstream'
HOST_UTIL = 'Host Utilization'
HOST_HISTORY = 'Host History'

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

    if target == 'all_jobs_modes':
        values.append(JOBS_STATS)
        values.append(TOTAL_BUILDS)
        values.append(PASS_PCT)
        values.append(PASS_DUR)
    if target == 'job_names':
        values.extend(sorted(jdq_client.job_names()))
    elif target == 'host_names':
        values = jdq_client.host_names()
    elif 'parameter_names:' in target:
        pfx, jobs = target.split(':')
        job_names = _parse_multi(jobs)
        for job_name in job_names:
            for p_name in jdq_client.parameter_names(job_name=job_name):
                if p_name not in values:
                    values.append(p_name)
    else:
        pass # XXXrs - exception?

    values = sorted(values)
    logger.debug("values: {}".format(values))
    return jsonify(values)

def _zulu_time_to_ts_ms(t_str):
    dt = datetime.datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%S.%fZ")
    return int(dt.replace(tzinfo=pytz.utc).timestamp()*1000)

def _timeserie_results(*, target, from_ms, to_ms):
    """
    Target name is one of "job:<job_name>" or "host:<host_names>"
    """
    logger.info("start")
    tgt = target.get('target', None)
    if not tgt:
        err = 'target has no name: {}'.format(target)
        logger.exception(err)
        abort(404, ValueError(err))

    try:
        mode,name = tgt.split(':')
    except Exception as e:
        err = "incomprehensible target name {}".format(tgt)
        logger.exception(err)
        abort(404, ValueError(err))

    if mode == 'host':
        host_names = _parse_multi(name)
    elif mode == 'job':
        job_names = _parse_multi(name)
    else:
        err = "invalid mode {}".format(mode)
        logger.exception(err)
        abort(404, ValueError(err))


    logger.info("mode: {} name: {}".format(mode, name))
    # XXXrs - FUTURE will store end_time_ms so may have a query
    #         to show all builds overlapping time frame, not just
    #         starting in time frame.  This might mean fabricating
    #         lines with start/end at frame boundries but which
    #         "continue" beyond...
    resp = jdq_client.builds_by_time(start_time_ms=from_ms, end_time_ms=to_ms)
    logger.debug("resp: {}".format(resp))

    result_datapoints = []
    results = []
    for bld in resp['builds']:
        job_name = bld.get('job_name', 'unknown')
        built_on = bld.get('built_on', 'master')

        if mode == 'job' and job_name not in job_names:
            logger.debug("skipping build: {}".format(bld))
            continue

        if mode == 'host' and built_on not in host_names:
            logger.debug("skipping build: {}".format(bld))
            continue

        build_number = bld.get('build_number')
        start_time_ms = bld.get('start_time_ms')
        duration_ms = bld.get('duration_ms')
        end_time_ms = start_time_ms + duration_ms
        result = bld.get('result')

        # Result target name includes pass/abort/fail
        # so can be selected for color coding.
        target_pfx = "{} {} on {}".format(job_name, build_number, built_on)
        if result == 'SUCCESS':
            target = "{} pass".format(target_pfx)
        elif result == 'PENDING':
            target = "{} pending".format(target_pfx)
        elif result == 'ABORTED':
            target = "{} abort".format(target_pfx)
        elif result == 'FAILURE':
            target = "{} fail".format(target_pfx)

        # Discrete line for each build.
        results.append({'target': target,
                        'datapoints':[[duration_ms, start_time_ms],
                                      [duration_ms, end_time_ms]]})
        """
        # Older version keeping the duration line separate from the
        # result endpoints.
        results.append({'target': "{} duration".format(build_number),
                        'datapoints':[[duration_ms, start_time_ms],
                                      [duration_ms, end_time_ms]]})
        if result == 'SUCCESS':
            results.append({'target': "{} pass".format(build_number),
                            'datapoints': [[duration_ms, end_time_ms]]})
        elif result == 'PENDING':
            results.append({'target': "{} pass".format(build_number),
                            'datapoints': [[duration_ms, end_time_ms]]})
        elif result == 'ABORTED':
            results.append({'target': "{} abort".format(build_number),
                            'datapoints': [[duration_ms, end_time_ms]]})
        elif result == 'FAILURE':
            results.append({'target': "{} fail".format(build_number),
                            'datapoints': [[duration_ms, end_time_ms]]})
        """
    return results


def _all_jobs_table(*, from_ms, to_ms):

    # Only show info for active jobs...
    active_jobs = jdq_client.job_names()

    # XXXrs - FUTURE will store end_time_ms so may have a query
    #         to show all builds overlapping time frame, not just
    #         starting in time frame.
    resp = jdq_client.builds_by_time(start_time_ms=from_ms, end_time_ms=to_ms)
    job_info = {}
    job_info_empty = {'pass_cnt':0,
                      'pass_total_duration_ms':0,
                      'pass_avg_duration_s':0,
                      'fail_cnt':0,
                      'fail_total_duration_ms':0,
                      'fail_avg_duration_s':0,
                      'abort_cnt':0}

    for bld in resp['builds']:
        job_name = bld.get('job_name')
        if job_name not in active_jobs:
            continue

        jinfo = job_info.setdefault(job_name, copy.deepcopy(job_info_empty))

        result = bld.get('result', 'MISSING')
        if result == 'SUCCESS':
            jinfo['pass_cnt'] += 1
            jinfo['pass_total_duration_ms'] += bld.get('duration_ms', 0)
        elif result == 'FAILURE':
            jinfo['fail_cnt'] += 1
            jinfo['fail_total_duration_ms'] += bld.get('duration_ms', 0)
        elif result == 'ABORTED':
            jinfo['abort_cnt'] += 1

    # Calculate the averages
    for job_name, info in job_info.items():
        pass_cnt = info['pass_cnt']
        fail_cnt = info['fail_cnt']
        total_complete = pass_cnt + fail_cnt
        info['total_complete'] = total_complete

        pass_total_dur_ms = 0
        fail_total_dur_ms = 0

        info['pass_avg_duration_s'] = 0
        if pass_cnt:
            pass_total_dur_ms = info['pass_total_duration_ms']
            info['pass_avg_duration_s'] = int((pass_total_dur_ms/pass_cnt)/1000)

        info['fail_avg_duration_s'] = 0
        if fail_cnt:
            fail_total_dur_ms = info['fail_total_duration_ms']
            info['fail_avg_duration_s'] = int((fail_total_dur_ms/fail_cnt)/1000)

        info['total_avg_duration_s'] = 0
        if total_complete:
            total_dur_ms = pass_total_dur_ms + fail_total_dur_ms
            info['total_avg_duration_s'] = int((total_dur_ms/total_complete)/1000)

        info['pass_pct'] = 0
        if total_complete:
            info['pass_pct'] = (pass_cnt*100)/total_complete

    # Build the table output
    columns = [
        {"text":"Job Name", "type":"string"},
        {"text":"Total Complete", "type":"number"},
        {"text":"Total Avg Time", "type":"number"},
        {"text":"Pass", "type":"number"},
        {"text":"Pass Avg Time", "type":"number"},
        {"text":"Fail", "type":"number"},
        {"text":"Fail Avg Time", "type":"number"},
        {"text":"Abort", "type":"number"},
        {"text":"Pass %", "type":"number"}
    ]
    rows = []
    if job_info:
        job_to_url = {i['job_name']:i['job_url'] for i in jdq_client.job_info()}
        for job_name, info in job_info.items():
            rows.append([job_name,
                         info['total_complete'],
                         info['total_avg_duration_s'],
                         info['pass_cnt'],
                         info['pass_avg_duration_s'],
                         info['fail_cnt'],
                         info['fail_avg_duration_s'],
                         info['abort_cnt'],
                         info['pass_pct']])
    return [{"columns": columns, "rows": rows, "type" : "table"}]

def _jobs_trends_table(*, table_mode):

    build_cnt_trends = [
            {'colhdr': 'Prev 24h', 'key': 'build_cnt', 'subkey': 'prev_24h'},
            {'colhdr': 'Last 24h', 'key': 'build_cnt', 'subkey': 'last_24h'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},


            {'colhdr': 'Prev 7d', 'key': 'build_cnt', 'subkey': 'prev_7d'},
            {'colhdr': 'Last 7d', 'key': 'build_cnt', 'subkey': 'last_7d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},

            {'colhdr': 'Prev 30d', 'key': 'build_cnt', 'subkey': 'prev_30d'},
            {'colhdr': 'Last 30d', 'key': 'build_cnt', 'subkey': 'last_30d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'}
    ]

    pass_pct_trends = [
            {'colhdr': 'Prev 24h', 'key': 'pass_pct', 'subkey': 'prev_24h'},
            {'colhdr': 'Last 24h', 'key': 'pass_pct', 'subkey': 'last_24h'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},

            {'colhdr': 'Prev 7d', 'key': 'pass_pct', 'subkey': 'prev_7d'},
            {'colhdr': 'Last 7d', 'key': 'pass_pct', 'subkey': 'last_7d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},

            {'colhdr': 'Prev 30d', 'key': 'pass_pct', 'subkey': 'prev_30d'},
            {'colhdr': 'Last 30d', 'key': 'pass_pct', 'subkey': 'last_30d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'}
    ]

    pass_duration_trends = [
            {'colhdr': 'Prev 24h', 'key': 'pass_avg_duration_s', 'subkey': 'prev_24h'},
            {'colhdr': 'Last 24h', 'key': 'pass_avg_duration_s', 'subkey': 'last_24h'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},

            {'colhdr': 'Prev 7d', 'key': 'pass_avg_duration_s', 'subkey': 'prev_7d'},
            {'colhdr': 'Last 7d', 'key': 'pass_avg_duration_s', 'subkey': 'last_7d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'},

            {'colhdr': 'Prev 30d', 'key': 'pass_avg_duration_s', 'subkey': 'prev_30d'},
            {'colhdr': 'Last 30d', 'key': 'pass_avg_duration_s', 'subkey': 'last_30d'},
            {'colhdr': 'Chg%', 'func': 'pct_chg'}
    ]

    if table_mode == TOTAL_BUILDS:
        job_trends = build_cnt_trends
    elif table_mode == PASS_PCT:
        job_trends = pass_pct_trends
    elif table_mode == PASS_DUR:
        job_trends = pass_duration_trends
    else:
        err = "invalid table mode {}".format(table_mode)
        logger.exception(err)
        abort(404, ValueError(err))

    columns = [{"text":"Job Name", "type":"string"}]
    for jt in job_trends:
        if 'colhdr' not in jt:
            continue
        columns.append({"text":jt['colhdr'], "type":"number"})

    rows = []
    for job in jdq_client.job_info():
        vals = []
        row = [job.get('job_name', 'Unknown')]
        ppd = job.get('default_postprocessor_data', {})
        have_data = False
        for jt in job_trends:
            func = jt.get('func', None)
            if func is None:
                val = ppd.get(jt['key'],{}).get(jt['subkey'], 0)
                vals.append(val)
                row.append(val)
                if val:
                    have_data = True
                continue
            if func == 'pct_chg':
                # XXXrs - assumes positions of previous two values
                v0 = vals[0]
                v1 = vals[1]
                vals = [] # XXXrs - assumes clear previous values
                if not v0:
                    row.append('nan')
                else:
                    row.append(((v1-v0)/v0)*100)
        if have_data:
            rows.append(row)

    return [{"columns": columns, "rows": rows, "type" : "table"}]


def _map_result(result):
    """
    Map the result string to a numeric value to allow for threshold
    coloration on Grafana.  Can then be mapped back to string.

    Sadly, Grafana only allows 3 colors based on thresholds.
    Place pending between success and aborted and the panel
    can decide.  Failure is not an option :)
    """
    if result == 'SUCCESS':
        return 0
    if result == 'PENDING':
        return 1
    if result == 'ABORTED':
        return 2
    # Presume failure
    return 3

def _host_metrics(*, item):
    avg_idle = "n/a"
    avg_user = "n/a"
    avg_system = "n/a"
    host_metrics = item.get('host_metrics', None)
    if host_metrics is not None:
        avg_idle = host_metrics.get('cpu_avg_idle', "n/a")
        avg_user = host_metrics.get('cpu_avg_user', "n/a")
        avg_system = host_metrics.get('cpu_avg_system', "n/a")
    return (avg_idle, avg_user, avg_system)

def _job_table(*, job_names, parameter_names, from_ms, to_ms):

    rows = []
    columns = [{"text":"Job Name", "type":"string"},
               {"text":"Build No.", "type":"string"},
               {"text":"Start Time", "type":"time"},
               {"text":"Duration (s)", "type":"number"},
               {"text":"Built On", "type": "string"},
               {"text":"Idle%", "type": "string"},
               {"text":"User%", "type": "string"},
               {"text":"Sys%", "type": "string"},
               {"text":"Result", "type":"string"}]
    for name in parameter_names:
        columns.append({"text": name, "type":"string"})

    query = {'$and': [{'start_time_ms':{'$gt': from_ms}},
                      {'start_time_ms':{'$lt': to_ms}}]}

    for job_name in job_names:
        resp = jdq_client.find_builds(job_name=job_name,
                                      query=query,
                                      projection={'start_time_ms': 1,
                                                  'duration_ms': 1,
                                                  'built_on': 1,
                                                  'host_metrics': 1,
                                                  'result': 1,
                                                  'parameters': 1})
        for bnum,item in resp.items():
            duration_s = int(item.get('duration_ms', 0)/1000)
            (avg_idle, avg_user, avg_system) = _host_metrics(item=item)
            vals = [job_name,
                    int(bnum),
                    item.get('start_time_ms', 0),
                    duration_s,
                    item.get('built_on', 'unknown'),
                    avg_idle,
                    avg_user,
                    avg_system,
                    _map_result(item.get('result'))]
            for name in parameter_names:
                vals.append(item.get('parameters', {}).get(name, "N/A"))
            rows.append(vals)
    return [{"columns": columns, "rows": rows, "type" : "table"}]


def _downstream_jobs_table(*, job_name, build_number):

    rows = []
    columns = [{"text":"Job Name", "type":"string"},
               {"text":"Build No.", "type":"string"},
               {"text":"Start Time", "type":"time"},
               {"text":"Duration (s)", "type":"number"},
               {"text":"Built On", "type": "string"},
               {"text":"Idle%", "type": "string"},
               {"text":"User%", "type": "string"},
               {"text":"Sys%", "type": "string"},
               {"text":"Result", "type":"string"}]

    down = jdq_client.downstream(job_name=job_name, bnum=build_number)
    if not down or 'downstream' not in down:
        return [{"columns": columns, "rows": rows, "type" : "table"}]
    ds_items = down.get('downstream', [])
    if not ds_items:
        return [{"columns": columns, "rows": rows, "type" : "table"}]
    for item in ds_items:
        name = item.get('job_name')
        bnum = item.get('build_number')
        detail = jdq_client.find_builds(job_name=name,
                                        query={'_id': bnum},
                                        projection={'duration_ms': 1,
                                                    'start_time_ms': 1,
                                                    'built_on': 1,
                                                    'host_metrics': 1,
                                                    'result': 1})
        if bnum not in detail:
            continue
        detail = detail[bnum]
        duration_s = int(detail.get('duration_ms', 0)/1000)
        (avg_idle, avg_user, avg_system) = _host_metrics(item=detail)
        vals = [name,
                int(bnum),
                detail.get('start_time_ms', 0),
                duration_s,
                detail.get('built_on', 'unknown'),
                avg_idle,
                avg_user,
                avg_system,
                _map_result(detail.get('result'))]
        rows.append(vals)
    return [{"columns": columns, "rows": rows, "type" : "table"}]

def _host_util_table(*, from_ms, to_ms):

    period_ms = to_ms-from_ms

    rows = []
    columns = [{"text":"Host Name", "type":"string"},
               {"text":"Builds", "type":"number"},
               {"text":"Total Build Time (s)", "type":"number"},
               {"text":"Utilization %", "type":"number"}]

    builds = jdq_client.builds_active_between(
                        start_time_ms=from_ms, end_time_ms=to_ms)

    host_data = {}
    for build in builds['builds']:
        '''
        Builds look like:

            {'build_number': '891',
             'built_on': 'kvmhost5-megavm1',
             'duration_ms': 4058802,
             'end_time_ms': 1603335618236,
             'job_name': 'UbmPerfTest',
             'result': 'SUCCESS',
             'start_time_ms': 1603331559434}
        '''
        host = build['built_on']
        bstart_ms = build['start_time_ms']
        bend_ms = build['end_time_ms']
        data = host_data.setdefault(host, {'builds': 0,
                                           'build_time_ms': 0})
        start_ms = max(from_ms, bstart_ms)
        end_ms = min(to_ms, bend_ms)
        data['builds'] += 1
        data['build_time_ms'] += (end_ms-start_ms)

    for host in jdq_client.host_names():
        if host not in host_data:
            rows.append([host, 0, 0, 0])
            continue
        data = host_data[host]
        ttime_ms = data['build_time_ms']
        util_pct = (ttime_ms/period_ms)*100
        rows.append([host, data['builds'], int(ttime_ms/1000), util_pct])
    return [{"columns": columns, "rows": rows, "type" : "table"}]


def _host_history_table(*, host_names, from_ms, to_ms):

    period_ms = to_ms-from_ms

    rows = []
    columns = [{"text":"Host Name", "type":"string"},
               {"text":"Job Name", "type":"string"},
               {"text":"Build No.", "type":"string"},
               {"text":"Start Time", "type":"time"},
               {"text":"Duration (s)", "type":"number"},
               {"text":"Result", "type":"string"}]

    builds = jdq_client.builds_active_between(
                        start_time_ms=from_ms, end_time_ms=to_ms)

    host_builds = {}
    for build in builds['builds']:
        '''
        Builds look like:

            {'build_number': '891',
             'built_on': 'kvmhost5-megavm1',
             'duration_ms': 4058802,
             'end_time_ms': 1603335618236,
             'job_name': 'UbmPerfTest',
             'result': 'SUCCESS',
             'start_time_ms': 1603331559434}
        '''
        host = build['built_on']
        if host not in host_names:
            continue

        job_name = build['job_name']
        build_num = build['build_number']
        bstart_ms = build['start_time_ms']
        bduration_s = int(build['duration_ms']/1000)
        result = _map_result(build['result'])

        rows.append([host, job_name, build_num,
                     bstart_ms, bduration_s, result])

    return [{"columns": columns, "rows": rows, "type" : "table"}]

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

    """
    # Not used
    freq_ms = req.get('intervalMs', None)
    if not freq_ms:
        abort(404, Exception('intervalMs missing'))
    logger.info("freq_ms: {}".format(freq_ms))
    """

    data_format = None

    for target in req['targets']:
        t_type = target.get('type', None)
        if not t_type:
            abort(404, Exception('target type missing'))
        if not data_format:
            data_format = t_type
        elif data_format != t_type:
            abort(404, Exception('mixed target data format (type)'))

    results = []
    if data_format == 'timeserie':
        for target in req['targets']:
            results.extend(_timeserie_results(target=target, from_ms=from_ts_ms, to_ms=to_ts_ms))
        return jsonify(results)

    if data_format != 'table':
        abort(404, Exception('unknown target data format (type) {}'.format(data_format)))

    # Table
    if len(req['targets']) > 1:
        abort(404, Exception('only single target allowed for table'))
    target = req['targets'][0]
    fields = target.get('target', "").split(':')
    if not fields:
        abort(404, Exception('missing target (job name)'))
    table_mode = _parse_multi(fields[0])
    if JOBS_STATS in table_mode:
        results = _all_jobs_table(from_ms=from_ts_ms, to_ms=to_ts_ms)
    elif TOTAL_BUILDS in table_mode:
        results = _jobs_trends_table(table_mode=TOTAL_BUILDS)
    elif PASS_PCT in table_mode:
        results = _jobs_trends_table(table_mode=PASS_PCT)
    elif PASS_DUR in table_mode:
        results = _jobs_trends_table(table_mode=PASS_DUR)
    elif DOWNSTREAM in table_mode:
        if len(fields) < 3:
            abort(404, Exception('invalid downstream target {}'
                                 .format(target)))
        job_name = _parse_multi(fields[1])
        build_number = _parse_multi(fields[2])
        results = _downstream_jobs_table(job_name=job_name,
                                         build_number=build_number)
    elif HOST_UTIL in table_mode:
        results = _host_util_table(from_ms=from_ts_ms, to_ms=to_ts_ms)
    elif HOST_HISTORY in table_mode:
        results = _host_history_table(host_names=_parse_multi(fields[1]),
                                      from_ms=from_ts_ms,
                                      to_ms=to_ts_ms)
    else:
        parameter_names = []
        if len(fields) == 2:
            parameter_names = _parse_multi(fields[1])

        # At this point, "table_mode" is a list of job names.
        results = _job_table(job_names=table_mode,
                             parameter_names=parameter_names,
                             from_ms=from_ts_ms, to_ms=to_ts_ms)

    logger.debug("table results: {}".format(results))
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
    app.run(host='0.0.0.0', port=3003, debug= True)
