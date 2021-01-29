#!/bin/bash

set -e

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

source "$XLRINFRADIR/bin/clusterCmds.sh"
initClusterCmds

cluster=$CLUSTER

TestsToRun=($TestCases)
TAP="AllTests.tap"

TMPDIR="${TMPDIR:-/tmp/`id -un`}/$JOB_NAME/functests"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

funcstatsd() {
    local name="${1//::/_}"
    local status="$2"
    local gitsha="$3"
    if [ "$status" = "PASS" ]; then
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numPass:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.status:0|g" | nc -w 1 -u $GRAPHITE 8125
    elif [ "$status" = "FAIL" ]; then
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numFail:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.status:1|g" | nc -w 1 -u $GRAPHITE 8125
    fi
}

sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100

gitsha=$(gitSha "$cluster")

AllTests="$(cloudXccli "$cluster" -c 'functests list' | tail -n+2)"
NumTests="${#TestsToRun[@]}"
hostname=`hostname -f`

echo "1..$(( $NumTests * $NUM_ITERATIONS ))" | tee "$TAP"
set +e
anyfailed=0
for ii in `seq 1 $NUM_ITERATIONS`; do
    echo "Iteration $ii"
    jj=1

    for Test in "${TestsToRun[@]}"; do
        logfile="$TMPDIR/${hostname//./_}_${Test//::/_}_$ii.log"

        echo "Running $Test on $cluster ..."
        if cloudXccli "$cluster" -c version 2>&1 | grep 'Error'; then
           genSupport "$cluster"
           echo "$cluster Crashed"
           exit 1
        elif [ $anyfailed -eq 1 ]
        then
            # cluster is up but got non zero return code. This means that
            # the ssh connection is lost. In such cases, just drive on with the
            # next test after restarting the cluster
            restartXcalar "$cluster"
            anyfailed=0
        fi
        echo "TESTCASE_START: $Test"
        time cloudXccli "$cluster" -c "functests run --allNodes --testCase $Test" 2>&1 | tee "$logfile"
        echo "TESTCASE_END: $Test"
        rc=${PIPESTATUS[0]}
        if [ $rc -ne 0 ]; then
            funcstatsd "$Test" "FAIL" "$gitsha"
            echo "not ok ${jj} - $Test-$ii" | tee -a $TAP
            anyfailed=1
        else
            if grep -q Error "$logfile"; then
                funcstatsd "$Test" "FAIL" "$gitsha"
                echo "Failed test output in $logfile at `date`"
                cat >&2 "$logfile"
                echo "not ok ${jj} - $Test-$ii"  | tee -a $TAP
                anyfailed=1
            else
                echo "Passed test at `date`"
                funcstatsd "$Test" "PASS" "$gitsha"
                echo "ok ${jj} - $Test-$ii"  | tee -a $TAP
            fi
        fi
        jj=$(( $jj + 1 ))
    done
done

exit $anyfailed

