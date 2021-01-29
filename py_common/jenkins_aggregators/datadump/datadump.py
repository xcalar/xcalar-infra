#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import datetime
import json
import logging
import os
import sys

sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.mongo import JenkinsMongoDB

cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.WARNING},
                        'JENKINS_HOST': {'default': None},
                        'JENKINS_DB_NAME': {'default': None}})

# It's log, it's log... :)
logging.basicConfig(level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                    handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

JMDB = JenkinsMongoDB()
DB = JMDB.jenkins_db().db

if __name__ == "__main__":

    import argparse
    argParser = argparse.ArgumentParser()
    argParser.add_argument('--outdir', required=True, type=str,
                                help='path to directory where per-job data should be written')
    args = argParser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    for cname in DB.list_collection_names():
        if cname.startswith('job_') and not cname.endswith('_meta'):
            namefields = cname.split('_')
            namefields.pop(0)
            jobname = "_".join(namefields)

            data = {}

            for doc in DB[cname].find({}):
                data[doc.get('_id')] = doc

            outfile = os.path.join(args.outdir, "{}.json".format(jobname))
            with open(outfile, "w+") as fp:
                logger.info("writing: {}".format(outfile))
                fp.write(json.dumps(data))
