#!/bin/bash
set -e
set -x

# Run tpc_tests.py against the given host/port.
# Assumes Xcalar server managed elsewhere.

say () {
    echo >&2 "$*"
}

say "TPCTests START ===="

say "TPCTests validate/default environment inputs ===="

# Construct TEST_ID
TEST_ID="${JOB_NAME}:${BUILD_ID}"

TEST_JDBC_PATH="${TEST_JDBC_PATH:-${XLRDIR}/src/sqldf/tests/test_jdbc.py}"

JDBC_PORT="${JDBC_PORT:-10000}"
API_PORT="${API_PORT:-443}"

TPCDS_USER="${TPCDS_USER:-admin}"
TPCDS_PASS="${TPCDS_PASS:-admin}"
TPCDS_WORKERS="${TPCDS_WORKERS:-0}"
TPCDS_SF="${TPCDS_SF:-10}"
TPCDS_PLAN="${TPCDS_PLAN:-/netstore/datasets/tpcds_new/sf_10}"
TPCDS_LOOPS="${TPCDS_LOOPS:-1}"
TPCDS_SEED="${TPCDS_SEED:-123}"
TPCDS_IMD_MERGE="${TPCDS_IMD_MERGE:-false}"

TPCH_USER="${TPCH_USER:-admin}"
TPCH_PASS="${TPCH_PASS:-admin}"
TPCH_WORKERS="${TPCH_WORKERS:-0}"
TPCH_SF="${TPCH_SF:-10}"
TPCH_PLAN="${TPCH_PLAN:-/netstore/datasets/tpch_new/sf_10}"
TPCH_LOOPS="${TPCH_LOOPS:-1}"
TPCH_SEED="${TPCH_SEED:-456}"
TPCH_IMD_MERGE="${TPCH_IMD_MERGE:-false}"

# XXXrs - this seems heavyweight but can't find anything else :(
say "TPCTests do XCE build to stage python packages for SDK ===="
cd $XLRDIR
cmBuild clean
cmBuild config debug
cmBuild xce

say "TPCTests run tpc_tests.py ===="


XLRINFRADIR="${XLRINFRADIR:-${XLRDIR}/xcalar-infra}"
pydir="${XLRINFRADIR}/jenkins/python"

# Common arguments...
ARGS=" --test_id=$TEST_ID --test_jdbc_path=$TEST_JDBC_PATH --jdbc_port=$JDBC_PORT"
ARGS="$ARGS --api_port=$API_PORT"

if [ $TPCDS_WORKERS -gt 0 ] || [ $TPCDS_IMD_MERGE = "true" ]; then
    if [ -z $TPCDS_JDBC_HOST ]; then
        say "ERROR: TPCDS_JDBC_HOST cannot be empty"
        exit 1
    fi
    ARGS="$ARGS --tpcds_jdbc_host=$TPCDS_JDBC_HOST"
    ARGS="$ARGS --tpcds_user=$TPCDS_USER"
    ARGS="$ARGS --tpcds_pass=$TPCDS_PASS"
    ARGS="$ARGS --tpcds_workers=$TPCDS_WORKERS --tpcds_sf=$TPCDS_SF --tpcds_plan=$TPCDS_PLAN"
    ARGS="$ARGS --tpcds_loops=$TPCDS_LOOPS --tpcds_seed=$TPCDS_SEED"
    if [ -n "$TPCDS_SKIPS" ]; then
        ARGS="$ARGS --tpcds_skips=$TPCDS_SKIPS"
    fi
fi
if [ $TPCDS_IMD_MERGE = "true" ]; then
    ARGS="$ARGS --tpcds_imd_merge"
fi
if [ $TPCH_WORKERS -gt 0 ] || [ $TPCH_IMD_MERGE = "true" ]; then
    if [ -z $TPCH_JDBC_HOST ]; then
        say "ERROR: TPCH_JDBC_HOST cannot be empty"
        exit 1
    fi
    ARGS="$ARGS --tpch_jdbc_host=$TPCH_JDBC_HOST"
    ARGS="$ARGS --tpch_user=$TPCH_USER"
    ARGS="$ARGS --tpch_pass=$TPCH_PASS"
    ARGS="$ARGS --tpch_workers=$TPCH_WORKERS --tpch_sf=$TPCH_SF --tpch_plan=$TPCH_PLAN"
    ARGS="$ARGS --tpch_loops=$TPCH_LOOPS --tpch_seed=$TPCH_SEED"
    if [ -n "$TPCH_SKIPS" ]; then
        ARGS="$ARGS --tpch_skips=$TPCH_SKIPS"
    fi
fi
if [ $TPCH_IMD_MERGE = "true" ]; then
    ARGS="$ARGS --tpch_imd_merge"
fi


set +e
python ${pydir}/tpc_tests.py $ARGS
rtn=$?

# If we happen to be running in a "cloud context"
# Expect $VmProvider and $CLUSTER to be set appropriately.
if [ ! -z $VmProvider ]; then
    # Generate support bundle(s)
    source "${XLRINFRADIR}/bin/clusterCmds.sh"
    initClusterCmds
    genSupport "${CLUSTER}"
else
    # XXXrs - WORKING HERE - Collect post-test artifacts from remote machine.
    #         Can/should this also be support bundles?
    say ""
fi
say "TPCTests END ===="
exit $rtn
