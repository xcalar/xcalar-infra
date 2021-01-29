#!/usr/bin/env python3
# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import os
import pprint
import sys
from pymongo import ReturnDocument

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.mongo import JenkinsMongoDB

if __name__ == '__main__':

    jmdb = JenkinsMongoDB()
    db = jmdb.jenkins_db()
    skipped = []
    ready_colls = {}
    update_colls = {}
    invalid_colls = {}
    total_empty = 0
    total_ready = 0
    total_update = 0
    total_invalid = 0
    for name in db.collection_names():
        process = False
        if name.startswith('_builds_by_time'):
            process = True
        if not process:
            if name.startswith('host_'):
                process = True
        if not process:
            if name.startswith('job_') and not name.endswith('_meta'):
                process = True

        if not process:
            skipped.append(name)
            continue

        coll = db.collection(name)
        update = 0
        ready = 0
        empty = 0
        invalid = 0
        for doc in coll.find({}):
            if 'NODATA' in doc:
                empty += 1
                total_empty += 1
                continue
            if 'end_time_ms' in doc:
                ready += 1
                total_ready += 1
                continue
            if 'start_time_ms' in doc and 'duration_ms' in doc:

                print("WOULD UPDATE: {} {}:\n{}".format(name, doc['_id'], pprint.pformat(doc)))

                '''
                start = doc['start_time_ms']
                dur = doc['duration_ms']
                end_time_ms = start+dur
                doc = coll.find_one_and_update(
                                {'_id': doc['_id']},
                                {'$set': {'end_time_ms': end_time_ms}},
                                return_document = ReturnDocument.AFTER)
                print("UPDATED: {}".format(pprint.pformat(doc)))
                '''

                update += 1
                total_update += 1
                continue
            else:
                print("INVALID: {} {}:\n{}".format(name, doc['_id'], pprint.pformat(doc)))
                invalid += 1
                total_invalid += 1

        if name in ready_colls or name in update_colls or name in invalid_colls:
            raise Exception("saw collection name {} twice?!?".format(name))

        info = {'update': update, 'ready': ready, 'invalid': invalid, 'empty': empty}
        if update > 0:
            update_colls[name] = info
        else:
            ready_colls[name] = info
        if invalid:
            invalid_colls[name] = info

    print("Skipped Collections ==========")
    print(pprint.pformat(skipped))
    print("Ready Collections ==========")
    print(pprint.pformat(ready_colls))
    print("Update Collections ==========")
    print(pprint.pformat(update_colls))
    print("Invalid Collections ==========")
    print(pprint.pformat(invalid_colls))
    print("Total Entries ==========")
    print("ready: {}".format(total_ready))
    print("update: {}".format(total_update))
    print("empty: {}".format(total_empty))
    print("invalid: {}".format(total_invalid))
