#!/usr/bin/env python3
# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import argparse
import logging
import os
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.mongo import JenkinsMongoDB, MongoDBKeepAliveLock, MongoDBKALockTimeout
from py_common.jenkins_aggregators import JenkinsJobMetaCollection

if __name__ == '__main__':

    cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.WARN}})

    # It's log, it's log... :)
    logging.basicConfig(
                    level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    '''
    argParser = argparse.ArgumentParser()
    argParser.add_argument("--job", default=[], type=str, action='append', dest='jobs',
                                help="only reset this (these) job(s)", metavar="name")
    argParser.add_argument("--do_reset", action="store_true",
                                help="do the reset")
    args = argParser.parse_args()
    '''

    jmdb = JenkinsMongoDB()
    db = jmdb.jenkins_db()
    job_to_builds = {}
    for name in db.collection_names():
        if not name.startswith('job_'):
            continue
        if name.endswith('_meta'):
            continue

        fields = name.split('_')
        job = "_".join(fields[1:])

        coll = db.collection(name)
        for doc in coll.find({}):
            cores = doc.get('analyzed_cores', None)
            if cores:
                for key,info in cores.items():
                    corefile_name = info.get('corefile_name', 'MISSING')
                    broken = False
                    if '.' in key or '/' in key:
                        broken = True
                    if corefile_name == 'MISSING':
                        broken = True
                    if '__' in corefile_name:
                        broken = True
                    if broken:
                        print("{} {}: key {} corefile_name {}".format(job, doc['_id'], key, corefile_name))
                        job_to_builds.setdefault(job, []).append(doc['_id'])

    for job_name, builds in job_to_builds.items():
        print("{} ===== {}\n{}".format(job_name, len(builds), builds))

    # See if user wants to proceed
    foo = input("Schedule reparse (y/N): ")
    if foo != 'y':
        sys.exit(0)

    print("scheduling...")

    # Flag matching builds for re-parse

    for job_name, builds in job_to_builds.items():
        process_lock_name = "{}_process_lock".format(job_name)
        process_lock_meta = {"reason": "locked by broken_corefile_name.py"}
        process_lock = MongoDBKeepAliveLock(db=jmdb.jenkins_db(), name=process_lock_name)
        try:
            process_lock.lock(meta=process_lock_meta)
        except MongoDBKALockTimeout as e:
            raise Exception("timeout acquiring {}".format(process_lock_name))

        meta_coll = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)
        meta_coll.reparse(builds=builds)
        process_lock.unlock()
