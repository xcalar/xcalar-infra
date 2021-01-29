#!/bin/bash -x

set -e

git clean -fxd -e "xcve"

export XLRDIR=`pwd`
export PATH="$XLRDIR/bin:$HOME/google-cloud-sdk/bin:$PATH"
TAP="AllTests.tap"

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

source "$XLRINFRADIR/bin/clusterCmds.sh"
initClusterCmds

# We need to build for xccli which is used by the systemTest
cmBuild clean
cmBuild config debug
cmBuild qa

installer=$INSTALLER_PATH
cluster=$CLUSTER

# get comma sep list of ip|hostname:port for each host in cluster, for runTest.py
node_arg=""
for node in $(getRealNodeNames "$cluster"); do
    ip_port="$node:18552"
    if [ ! -z "$node_arg" ]; then
        node_arg="$node_arg,$ip_port"
    else
        node_arg="$ip_port"
    fi
done

funcstatsd() {
    local name="${1//::/_}"
    local status="$2"
    local gitsha="$3"
    if [ "$status" = "PASS" ]; then
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.numPass:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.status:0|g" | nc -w 1 -u $GRAPHITE 8125
    elif [ "$status" = "FAIL" ]; then
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.numFail:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.systemtests.${name}.${cluster//./_}.status:1|g" | nc -w 1 -u $GRAPHITE 8125
    fi
}

export http_proxy=

# ENG-10020 commented this out since we moved the test into containers
#sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100

gitsha=$(gitSha "$cluster")

echo "1..$NUM_ITERATIONS" | tee "$TAP"
set +e
for ii in `seq 1 $NUM_ITERATIONS`; do
    Test="$SYSTEM_TEST_CONFIG-$NUM_USERS"
    python "$XLRDIR/src/bin/tests/systemTests/runTest.py" -n $NUM_USERS -i "$node_arg" -t $SYSTEM_TEST_CONFIG -w -c $XLRDIR/bin
    ret="$?"
    if [ "$ret" = "0" ]; then
        echo "Passed '$Test' at `date`"
        funcstatsd "$Test" "PASS" "$gitsha"
        echo "ok ${ii} - $Test-$ii"  | tee -a $TAP
    else
        genSupport "$cluster"
        funcstatsd "$Test" "FAIL" "$gitsha"
        echo "not ok ${ii} - $Test-$ii" | tee -a $TAP
        exit $ret
    fi
done
set -e

exit $ret
