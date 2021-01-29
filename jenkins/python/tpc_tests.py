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
import random
import shlex
import signal
import subprocess
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration

os.environ["XLR_PYSDK_VERIFY_SSL_CERT"] = "false"

cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.DEBUG}}) # XXXrs DEBUG!

# Configure logging
logging.basicConfig(level=cfg.get('LOG_LEVEL'),
                    format="'%(asctime)s - %(levelname)s - %(threadName)s - %(funcName)s - %(message)s",
                    handlers=[logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)

# Arrange for orderly shutdown on signal 

WAIT_TIMEOUT = 10
SHUTDOWN = False
def do_shutdown(signum, frame):
    logger.info("signal {}".format(signum))
    SHUTDOWN = True


signal.signal(signal.SIGINT, do_shutdown)
signal.signal(signal.SIGHUP, do_shutdown)
signal.signal(signal.SIGTERM, do_shutdown)

"""
XXXrs - FUTURE - performance options...
if [ -z "$PERF_PREFIX" ]; then
    perf_options=""
else
    export NETSTORE="${NETSTORE:-/netstore/qa/jenkins}"
    RESULTS_PATH="${NETSTORE}/${JOB_NAME}/${BUILD_ID}"
    mkdir -p "$RESULTS_PATH"
    perf_options="-o ${RESULTS_PATH}/${PERF_PREFIX}"
fi
"""

def test_jdbc_cmds(*, tpctype, argsdict, imd):
    """
    Return a pair of commands: (load_cmd, test_cmd)
    """
    sid = random.randint(1000000000,9999999999)
    xcSess = "{}Sess_{}".format(tpctype, sid)
    sdkSess = "{}SdkSess_{}".format(tpctype, sid)

    # Base part of any commands...
    cmd = "{} --jdbc-port {} -a {} --ignore-MoneyRescale"\
          .format(argsdict['test_jdbc_path'],
                  argsdict['jdbc_port'],
                  argsdict['api_port'])

    cmd += " -U {}".format(argsdict["{}_user".format(tpctype)])
    cmd += " -P {}".format(argsdict["{}_pass".format(tpctype)])
    cmd += " -H {}".format(argsdict["{}_jdbc_host".format(tpctype)])
    cmd += " -t test_{}_xd_dataflows".format(tpctype)
    cmd += " -p {}".format(argsdict["{}_plan".format(tpctype)])
    cmd += " --SF {}".format(argsdict["{}_sf".format(tpctype)])
    cmd += " --xcSess {}".format(xcSess)
    cmd += " --sdkSess {}".format(sdkSess)
    load_cmd = "{} -w 0 -K".format(cmd)

    cmd += " --ignore-xcalar" # ENG-8720
    cmd += " --loop {} -s {}".format(argsdict["{}_loops".format(tpctype)],
                                     argsdict["{}_seed".format(tpctype)])

    skips = argsdict.get("{}_skips".format(tpctype), None)
    if skips:
        for name in skips.split(','):
            cmd += " --skip {}".format(name)

    if imd:
        cmd += " -w 1 --testMergeOp"
    else:
        cmd += " -w {}".format(argsdict["{}_workers".format(tpctype)])

    return (load_cmd, cmd)

def subprocs_done(*, subprocs):
    done = True
    for info in subprocs:
        rc = info['rc']
        if rc is not None:
            continue
        p = info['proc']
        rc = p.poll()
        if rc is None:
            done = False
            continue
        info['rc'] = rc
        try:
            p.wait(timeout=WAIT_TIMEOUT)
        except subprocess.TimeoutExpired:
            logger.exception()
    return done

def subprocs_stop(*, subprocs):
    for info in subprocs:
        if info['rc'] is not None:
            continue
        info['proc'].send_signal(signal.SIGTERM)
        try:
            info['rc'] = p.wait(timeout=WAIT_TIMEOUT)
        except subprocess.TimeoutExpired:
            logger.exception()

def subprocs_rc(*, subprocs):
    # return first non-zero exit code
    for info in subprocs:
        rc = info['rc']
        if rc:
            return rc
    return 0

if __name__ == '__main__':


    parser = argparse.ArgumentParser()

    parser.add_argument("--test_id", help="Test ID string", required=True)
    parser.add_argument("--test_jdbc_path", help="Path to test_jdbc", required=True)

    parser.add_argument("--jdbc_port", help="JDBC server port", default=10000)
    parser.add_argument("--api_port", help="API port", default=443)

    # TPC-DS
    parser.add_argument("--tpcds_user", help="username", default="admin")
    parser.add_argument("--tpcds_pass", help="password", default="admin")
    parser.add_argument("--tpcds_imd_merge", help="Do TPC-DS IMD merge test", action="store_true")
    parser.add_argument("--tpcds_jdbc_host", help="TPC-DS JDBC server hostname")
    parser.add_argument("--tpcds_sf", help="TPC-DS Scale Factor", default=10)
    parser.add_argument("--tpcds_plan", help="TPC-DS Plan Path", default="/netstore/datasets/tpcds_new/sf_10")
    parser.add_argument("--tpcds_workers", help="TPC-DS workers", type=int, default=0)
    parser.add_argument("--tpcds_loops", help="TPC-DS test iterations (loops)", type=int, default=1)
    parser.add_argument("--tpcds_seed", help="TPC-DS random seed", type=int, default=123)
    parser.add_argument("--tpcds_skips", help="Comma-separated list of TPC-DS queries to skip")

    # TPC-H
    parser.add_argument("--tpch_user", help="username", default="admin")
    parser.add_argument("--tpch_pass", help="password", default="admin")
    parser.add_argument("--tpch_imd_merge", help="Do TPC-H IMD merge test", action="store_true")
    parser.add_argument("--tpch_jdbc_host", help="TPC-H JDBC server hostname")
    parser.add_argument("--tpch_sf", help="TPC-H Scale Factor", default=10)
    parser.add_argument("--tpch_plan", help="TPC-H Plan Path", default="/netstore/datasets/tpch_new/sf_10")
    parser.add_argument("--tpch_workers", help="TPC-H workers", type=int, default=0)
    parser.add_argument("--tpch_loops", help="TPC-H test iterations (loops)", type=int, default=1)
    parser.add_argument("--tpch_seed", help="TPC-H random seed", type=int, default=456)
    parser.add_argument("--tpch_skips", help="Comma-separated list of TPC-H queries to skip")

    args = parser.parse_args()
    argsdict = vars(args)

    cmds = []
    if argsdict["tpcds_workers"] > 0:
        cmds.append(test_jdbc_cmds(tpctype="tpcds", argsdict=argsdict, imd=False))

    if argsdict["tpcds_imd_merge"]:
        cmds.append(test_jdbc_cmds(tpctype="tpcds", argsdict=argsdict, imd=True))

    if argsdict["tpch_workers"] > 0:
        cmds.append(test_jdbc_cmds(tpctype="tpch", argsdict=argsdict, imd=False))

    if argsdict["tpch_imd_merge"]:
        cmds.append(test_jdbc_cmds(tpctype="tpch", argsdict=argsdict, imd=True))

    load_cmds, test_cmds = zip(*cmds)

    logger.debug("load_cmds: {}".format(load_cmds))
    logger.debug("test_cmds: {}".format(test_cmds))

    subprocs = []
    for idx,cmd in enumerate(load_cmds):
        # XXXrs - There is some brain-dead code in Qa.py that can
        #         result in "file exists" errors when multiple
        #         test_jdbc.py instances are launched "too quickly"
        #         one after the other.  Attempt to mitigate here since
        #         it takes eons to get a trivial change through
        #         review etc. etc. etc.
        #
        #         I fixed the code in trunk, but still bites us on 2.3
        #         This sleep can go away eventually but for now...
        time.sleep(10)
        logger.debug("start load cmd: {}".format(cmd))
        p = subprocess.Popen(shlex.split(cmd))
        subprocs.append({'proc': p, 'rc': None})
    while not SHUTDOWN and not subprocs_done(subprocs=subprocs):
        time.sleep(1)
    if SHUTDOWN:
        subprocs_stop(subprocs=subprocs)
        sys.exit(1)

    rc = subprocs_rc(subprocs=subprocs)
    if (rc):
        sys.exit(rc)

    subprocs = []
    for idx,cmd in enumerate(test_cmds):
        time.sleep(10) # See rant above :)
        logger.debug("start test cmd: {}".format(cmd))
        p = subprocess.Popen(shlex.split(cmd))
        subprocs.append({'proc': p, 'rc': None})
    while not SHUTDOWN and not subprocs_done(subprocs=subprocs):
        time.sleep(1)
    if SHUTDOWN:
        subprocs_stop(subprocs=subprocs)
        sys.exit(1)
    sys.exit(subprocs_rc(subprocs=subprocs))
