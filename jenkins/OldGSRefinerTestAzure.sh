#!/bin/bash
set -e
set -x

say () {
    echo >&2 "$*"
}

say "OldGSRefinerTest START ===="

if [ -z $HOST ]; then
    say "ERROR: HOST cannot be empty"
    exit 1
fi
if [ -z $PORT ]; then
    say "ERROR: PORT cannot be empty"
    exit 1
fi
if [ -z $USER ]; then
    say "ERROR: USER cannot be empty"
    exit 1
fi
if [ -z $PASSWORD ]; then
    say "ERROR: PASSWORD cannot be empty"
    exit 1
fi
if [ -z $BATCHES ]; then
    say "ERROR: BATCHES cannot be empty"
    exit 1
fi
if [ -z $INSTANCES ]; then
    say "ERROR: INSTANCES cannot be empty"
    exit 1
fi
if [ -z $CLUSTER ]; then
    say "ERROR: CLUSTER cannot be empty"
    exit 1
fi


say "OldGSRefinerTest BUILD ===="
# XXXrs - Tech Debt?
cd $XLRDIR
cmBuild clean
cmBuild config debug
# XXXrs - Only want to get the python in place to run our Python script,
# but can't # figure out the lightest-weight make target.
# "xce" is (very) heavyweight but works reliably, so just use it (forever?).
cmBuild xce

# XXXrs - Tried to get away with the following, but too easy to get out-of-sync
#python3 -m pip install -U pip
#curl https://storage.googleapis.com/repo.xcalar.net/xcalar-sdk/requirements-2.2.0.txt --output requirements.txt
#pip install -r requirements.txt

say "OldGSRefinerTest RUN dataflow_engine.py ===="

export XLRINFRADIR="${XLRINFRADIR:-${XLRDIR}/xcalar-infra}"
test_id="${JOB_NAME}:${BUILD_ID}"
pydir="${XLRINFRADIR}/jenkins/python"

host_options="--host $HOST --port $PORT"
user_options="--user $USER --pass $PASSWORD"
load_options="--batches $BATCHES --instances $INSTANCES"
config_options="--config ${pydir}/old_gs_refiner_azure.json"

set +e
python ${pydir}/dataflow_engine.py --test_id $test_id $host_options $user_options $load_options $config_options
rtn=$?
if [ $rtn -ne 0 ]; then
    # Generate support bundle(s)
    source "${XLRINFRADIR}/bin/clusterCmds.sh"
    initClusterCmds
    genSupport "${CLUSTER}"
fi
say "OldGSRefinerTest END ===="
exit $rtn
