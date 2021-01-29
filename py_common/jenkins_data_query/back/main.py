#!/usr/bin/env python3

# Copyright 2019-2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import datetime
import logging
import os
import pprint
import pytz
import random
import re
import statistics
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.DEBUG},
                        'JENKINS_HOST': {'required': True}})

from py_common.mongo import JenkinsMongoDB
from py_common.jenkins_aggregators import JenkinsAllJobIndex
from py_common.jenkins_aggregators import JenkinsJobDataCollection
from py_common.jenkins_aggregators import JenkinsJobMetaCollection

from flask import Flask, request, jsonify, json, abort, make_response
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=cfg.get('LOG_LEVEL'),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

app = Flask(__name__)
cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'

jenkins_host = cfg.get('JENKINS_HOST')
jmdb = JenkinsMongoDB()
jdb = jmdb.jenkins_db()

methods=['GET']
@app.route('/', methods=methods)
@cross_origin()
def test_connection():
    """
    / should return 200 ok.
    """
    return "Connection check A-OK!"

@app.route('/jenkins_jobs', methods=methods)
@cross_origin()
def jenkins_jobs():
    jobs = []
    for job_name in jmdb.active_jobs():
        jjmc = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)
        jobs.append({'job_name': job_name,
                     'job_url': "http://{}/job/{}".format(jenkins_host, job_name),
                     'default_postprocessor_data': jjmc.get_data(key='default_postprocessor')})
    return make_response(jsonify({'jobs': jobs}))

@app.route('/jenkins_hosts', methods=methods)
@cross_origin()
def jenkins_hosts():
    hosts = []
    for host_name in jmdb.active_hosts():
        hosts.append({'host_name': host_name,
                      'host_url': "http://{}/computer/{}".format(jenkins_host, host_name)})
    return make_response(jsonify({'hosts': hosts}))

def _get_upstream(*, job_name, build_number):
    upstream = []
    # XXXrs - assumes collection name! Fix!
    doc = jdb.db["job_{}".format(job_name)].find_one({'_id': build_number}, projection={'upstream':1})
    logger.debug(doc)
    if not doc:
        return None
    for item in doc.get('upstream', []):
        us_job = item.get('job_name', None)
        us_bnum = str(item.get('build_number', None))
        if not us_job or not us_bnum:
            continue
        upstream.append({'job_name': us_job,
                         'build_number': us_bnum,
                         'upstream': _get_upstream(job_name=us_job,
                                                    build_number=us_bnum)})
    if not len(upstream):
        return None
    return upstream

@app.route('/jenkins_upstream', methods=methods)
@cross_origin()
def jenkins_upstream():
    """
    """
    job_name = request.args.get('job_name', None)
    if not job_name:
        abort(400, 'missing downstream job_name')

    build_number = request.args.get('build_number', None)
    if not build_number:
        abort(400, 'missing downstream build_number')

    return make_response(jsonify({'upstream':
                                  _get_upstream(job_name=job_name,
                                                build_number=build_number)}))

def _get_downstream(*, job_name, bnum, coll):
    key = "{}:{}".format(job_name, bnum)
    doc = coll.find({'_id': key})
    if not doc:
        return None
    pass

@app.route('/jenkins_downstream', methods=methods)
@cross_origin()
def jenkins_downstream():
    """
    """
    job_name = request.args.get('job_name', None)
    if not job_name:
        abort(400, 'missing upstream job_name')

    build_number = request.args.get('build_number', None)
    if not build_number:
        abort(400, 'missing upstream build_number')

    alljob_idx = JenkinsAllJobIndex(jmdb=jmdb)
    downstream = alljob_idx.downstream_jobs(job_name=job_name, bnum=build_number)
    return make_response(jsonify(downstream))

@app.route('/jenkins_find_builds', methods=methods)
@cross_origin()
def jenkins_find_builds():
    job_name = request.args.get('job_name', None)
    if not job_name:
        abort(400, 'missing job_name')
    try:
        query = request.args.get('query', '{}')
        logger.debug('query: {}'.format(query))
        query = json.loads(query)
    except Exception as e:
        abort(400, str(e))

    try:
        proj = request.args.get('projection', '{}')
        logger.debug('proj: {}'.format(proj))
        proj = json.loads(proj)
    except Exception as e:
        abort(400, str(e))

    try:
        found = {}
        args = {}
        if proj:
            args['projection'] = proj
        # XXXrs - assumes collection name! Fix!
        for doc in jdb.db["job_{}".format(job_name)].find(query, **args):
            logger.debug('doc: {}'.format(pprint.pformat(doc)))
            doc['build_url'] = "http://{}/job/{}/{}/"\
                               .format(jenkins_host, job_name, doc['_id'])
            found[doc['_id']] = doc
        return make_response(jsonify(found))
    except Exception as e:
        abort(400, str(e))

@app.route('/jenkins_builds_by_time', methods=methods)
@cross_origin()
def jenkins_builds_by_time():
    start_time_ms = int(request.args.get('start_time_ms', 0))
    end_time_ms = int(request.args.get('end_time_ms', time.time()*1000))
    alljob_idx = JenkinsAllJobIndex(jmdb=jmdb)
    return make_response(jsonify(alljob_idx.builds_by_time(
                                    start_time_ms=start_time_ms,
                                    end_time_ms=end_time_ms)))

@app.route('/jenkins_builds_active_between', methods=methods)
@cross_origin()
def jenkins_builds_active_between():
    start_time_ms = int(request.args.get('start_time_ms', 0))
    end_time_ms = int(request.args.get('end_time_ms', time.time()*1000))
    alljob_idx = JenkinsAllJobIndex(jmdb=jmdb)
    return make_response(jsonify(alljob_idx.builds_active_between(
                                    start_time_ms=start_time_ms,
                                    end_time_ms=end_time_ms)))

@app.route('/jenkins_job_parameters', methods=methods)
@cross_origin()
def jenkins_job_parameters():
    job_name = request.args.get('job_name', None)
    if not job_name:
        abort(400, 'missing job_name')

    # Find the latest build for the job in the DB and extract the parameter
    # names and return.

    # N.B.: this will give latest completed job, not latest job seen which may
    #       still be in progress, and is not yet in the "all_builds" list.
    all_builds = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb).all_builds()
    if not all_builds:
        return make_response(jsonify({}))

    latest_bnum = sorted([int(n) for n in all_builds])[-1]
    latest = JenkinsJobDataCollection(job_name=job_name, jmdb=jmdb).get_data(bnum=str(latest_bnum))
    if not latest:
        return make_response(jsonify({}))

    parameter_names = list(latest.get('parameters', {}).keys())
    return make_response(jsonify({"parameter_names":parameter_names}))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3005, debug=True)
