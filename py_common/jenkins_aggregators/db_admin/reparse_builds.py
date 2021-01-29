#!/usr/bin/env python3
# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import argparse
import datetime
import logging
import os
import pymongo
import pytz
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.mongo import JenkinsMongoDB, MongoDBKeepAliveLock, MongoDBKALockTimeout
from py_common.jenkins_aggregators import JenkinsAllJobIndex
from py_common.jenkins_aggregators import JenkinsJobMetaCollection
from py_common.jenkins_aggregators import JenkinsJobDataCollection

def get_ts(*, dt, tm, tz):

    (year, month, day) = dt.split("-")
    (hour, minute, second) = tm.split(":")

    dt = tz.localize(datetime.datetime(int(year), int(month), int(day),
                                       int(hour), int(minute), int(second)))
    return dt.timestamp()

def ts_to_date(*, ts, tz):
    """
    Returns (<date_str>, <hr_str>)
        where <date_str> is "YYYY-MM-DD" and <hr_str> is "00" through "23"
    """
    dt = datetime.datetime.fromtimestamp(ts, tz=tz)
    return ("{}-{:02d}-{:02d} {:02d}:{:02d}:{:02d}"
            .format(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second))

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
                                help="only consider builds from this (these) job(s)", metavar="name")
    argParser.add_argument("--bnum", default=[], type=str, action='append', dest='builds',
                                help="only reparse these specific builds (must supply exactly one job)", metavar="number")
    argParser.add_argument("--detail", action="store_true",
                                help="show build details")
    argParser.add_argument("--force", action="store_true",
                                help="force update without ask")

    argParser.add_argument('--prior_days', default=None, type=int,
                                help='defaults start_date to N days prior to today')
    argParser.add_argument('--start_ts', default=None, type=int,
                                help='start timestamp (s)')
    argParser.add_argument('--end_ts', default=None, type=int,
                                help='end timestamp (s)')

    argParser.add_argument('--start_date', default=None, type=str,
                                help='start date (YYYY-MM-DD) defaults to today')
    argParser.add_argument('--start_time', default=None, type=str,
                                help='start time (HH:MM:SS) defaults to 00:00:00')
    argParser.add_argument('--end_date', default=None, type=str,
                                help='end date (YYYY-MM-DD) defaults to today')
    argParser.add_argument('--end_time', default=None, type=str,
                                help='end time (HH:MM:SS) defaults to 23:59:59')
    argParser.add_argument('--tz', default="America/Los_Angeles", type=str,
                                help='timezone for inputs')

    args = argParser.parse_args()

    jmdb = JenkinsMongoDB()

    if len(args.builds):
        if len(args.jobs) != 1:
            raise ValueError("If --bnum only one --job allowed")

        # Re-parse only specific builds from a job

        # validate the job/builds
        job_name = args.jobs[0]
        active_jobs = jmdb.active_jobs()
        if job_name not in active_jobs:
            raise ValueError("{} is not an active job".format(job_name))

        meta_coll = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)
        all_builds = meta_coll.all_builds()
        for bnum in args.builds:
            if bnum not in all_builds:
                raise ValueError("{} is not a valid build number".format(bnum))

        # See if user wants to proceed
        if not args.force:
            foo = input("Proceed (y/N): ")
            if foo != 'y':
                sys.exit(0)

        print("proceeding...")

        # Flag builds for re-parse

        process_lock_name = "{}_process_lock".format(job_name)
        process_lock_meta = {"reason": "locked by reparse_builds.py"}
        process_lock = MongoDBKeepAliveLock(db=jmdb.jenkins_db(), name=process_lock_name)
        try:
            process_lock.lock(meta=process_lock_meta)
        except MongoDBKALockTimeout as e:
            raise Exception("timeout acquiring {}".format(process_lock_name))

        meta_coll.reparse(builds=args.builds)
        process_lock.unlock()
        sys.exit(0)

    # Re-parse builds selected by time period, optionally filtered by job name(s)
    tz = pytz.timezone(args.tz)
    now = datetime.datetime.now(tz=tz)

    default_start_date = "{}-{}-{}".format(now.year, now.month, now.day)
    default_end_date = default_start_date

    if args.prior_days is not None:
        prior = now-datetime.timedelta(days=args.prior_days)
        default_start_date = "{}-{}-{}".format(prior.year, prior.month, prior.day)

    start_ts = args.start_ts
    if not start_ts:
        start_dt = args.start_date
        if not start_dt:
            start_dt = default_start_date
        tm = args.start_time
        if not tm:
            tm = "00:00:00"
        start_ts = get_ts(dt=start_dt, tm=tm, tz=tz)

    end_ts = args.end_ts
    if not end_ts:
        end_dt = args.end_date
        if not end_dt:
            end_dt = default_end_date
        tm = args.end_time
        if not tm:
            tm = "23:59:59"
        dt_str = "{} {}".format(end_dt, tm)
        end_ts = get_ts(dt=end_dt, tm=tm, tz=tz)

    logger.debug("start: {}".format(ts_to_date(ts=start_ts, tz=tz)))
    logger.debug("end: {}".format(ts_to_date(ts=end_ts, tz=tz)))

    # Find all builds between start/end times

    alljob = JenkinsAllJobIndex(jmdb=jmdb)
    builds = alljob.builds_by_time(
                    full=True, # want ID and collection info for removal...
                    start_time_ms=(start_ts*1000),
                    end_time_ms=(end_ts*1000))

    builds = builds['builds'] # :/
    if not builds:
        print("NO BUILDS")
        sys.exit(0)

    job_to_builds = {}
    for build in builds:
        job_name = build['job_name']
        job_to_builds.setdefault(job_name, []).append(build)

    for job_name, builds in job_to_builds.items():
        if args.jobs and job_name not in args.jobs:
            continue
        bnums = [b['build_number'] for b in builds]
        print("Job: {} =====".format(job_name))
        if not args.detail:
            print("{}".format(bnums))
            print("=====")
            continue

        # Detail
        job_coll = JenkinsJobDataCollection(job_name=job_name, jmdb=jmdb)
        for bnum in bnums:
            doc = job_coll.get_data(bnum=bnum)
            print("Build: {} ---".format(job_name, bnum))
            print(doc)
        print("=====")

    # See if user wants to proceed
    if not args.force:
        foo = input("Proceed (y/N): ")
        if foo != 'y':
            sys.exit(0)

    print("proceeding...")

    # Flag matching builds for re-parse

    for job_name, builds in job_to_builds.items():
        if args.jobs and job_name not in args.jobs:
            continue
        bnums = [b['build_number'] for b in builds]
        process_lock_name = "{}_process_lock".format(job_name)
        process_lock_meta = {"reason": "locked by reparse_builds.py"}
        process_lock = MongoDBKeepAliveLock(db=jmdb.jenkins_db(), name=process_lock_name)
        try:
            process_lock.lock(meta=process_lock_meta)
        except MongoDBKALockTimeout as e:
            raise Exception("timeout acquiring {}".format(process_lock_name))

        meta_coll = JenkinsJobMetaCollection(job_name=job_name, jmdb=jmdb)
        meta_coll.reparse(builds=bnums)
        process_lock.unlock()
