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
import sys
import requests
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                        'BACKEND_HOST': {'required': True},
                        'BACKEND_PORT': {'required': True},
                        'TIMEZONE': {'default': 'America/Los_Angeles'}})
    
from flask import Flask, request
from flask import render_template, make_response, jsonify
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=cfg.get('LOG_LEVEL'),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

timezone = pytz.timezone(cfg.get('TIMEZONE'))

app = Flask(__name__)
cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'

methods=['GET']
@app.route('/', methods=methods)
@cross_origin()
def test_connection():
    """
    / should return 200 ok.
    """
    return "Connection check A-OK!"


@app.route('/jdq', methods=methods)
@cross_origin()
def jenkins_data_query_index():
    # XXXrs - WORKING HERE - want to put up a page with options that
    #         click through to other places here...
    return render_template("jmd_index.html")

def _get_jobs_data(*, start, end, host=None):
    args = "start={}&end={}".format(start, end)
    if host is not None:
        args += "&host={}".format(host)
    back_url = "http://{}:{}/jenkins_builds_by_time?{}"\
               .format(cfg.get('BACKEND_HOST'), cfg.get('BACKEND_PORT'), args)
    response = requests.get(back_url, verify=False) # XXXrs disable verify!
    rsp = response.json()
    logger.info("rsp {}".format(rsp))
    logger.info("rsp length: {}".format(len(rsp)))

    for item in rsp['jobs']:
        start_time_ms = item.get('start_time_ms', None)
        if not start_time_ms:
            fmt = "00/00/00 00:00:00"
        else:
            fmt = datetime.datetime.fromtimestamp(start_time_ms/1000, tz=timezone).strftime("%Y/%m/%d %H:%M:%S")
        item["start_time_fmt"] = fmt

        item["duration_s"] = int(item.get('duration_ms', 0)/1000)
    return rsp['jobs']

DAY = 60*60*24
WEEK = DAY*7

@app.route('/jenkins_builds_by_time', methods=methods)
@cross_origin()
def jenkins_builds_by_time():
    now = int(time.time())
    start = request.args.get('start', 0)
    end = request.args.get('end', now)
    host = request.args.get('host', None)
    jobs = _get_jobs_data(start=start, end=end, host=host)
    return render_template("jobs_table.html", jobs=jobs)

@app.route('/jenkins_jobs_last_1w', methods=methods)
@cross_origin()
def jenkins_jobs_last_1w():
    now = int(time.time())
    start = now-(WEEK)
    host = request.args.get('host', None)
    jobs = _get_jobs_data(start=start, end=now, host=host)
    return render_template("jobs_table.html", jobs=jobs)

@app.route('/jenkins_jobs_last_2w', methods=methods)
@cross_origin()
def jenkins_jobs_last_2w():
    now = int(time.time())
    start = now-(2*WEEK)
    host = request.args.get('host', None)
    jobs = _get_jobs_data(start=start, end=now, host=host)
    return render_template("jobs_table.html", jobs=jobs)

@app.route('/jenkins_jobs_last_30d', methods=methods)
@cross_origin()
def jenkins_jobs_last_30d():
    now = int(time.time())
    start = now-(30*DAY)
    host = request.args.get('host', None)
    jobs = _get_jobs_data(start=start, end=now, host=host)
    return render_template("jobs_table.html", jobs=jobs)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4001, debug=True)
