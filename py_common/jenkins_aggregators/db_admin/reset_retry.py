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
from py_common.jenkins_aggregators import JenkinsAllJobIndex

if __name__ == '__main__':

    cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.WARN}})

    # It's log, it's log... :)
    logging.basicConfig(
                    level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    argParser = argparse.ArgumentParser()
    argParser.add_argument("--job", default=[], type=str, action='append', dest='jobs',
                                help="only reset this (these) job(s)", metavar="name")
    argParser.add_argument("--do_reset", action="store_true",
                                help="do the reset")
    args = argParser.parse_args()

    jmdb = JenkinsMongoDB()
    db = jmdb.jenkins_db()
    for meta in db.job_meta_collection_names():
        if args.jobs:
            # Special knowledge...
            fields = meta.split('_')
            job = "_".join(fields[1:-1])
            if job not in args.jobs:
                continue

        if not args.do_reset:
            print("would reset: {}".format(meta))
            continue

        print("resetting {}".format(meta))
        db.collection(meta).find_one_and_delete({'_id': 'retry'})
