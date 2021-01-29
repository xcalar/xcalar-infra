#!/bin/bash

if [ ! -n "$XLRINFRADIR" ]; then
    echo "XLRINFRADIR must be set"
    return 1
fi

if [ ! -n "$NUM_INSTANCES" ]; then
    echo "NUM_INSTANCES must be set"
    return 1
fi

GRAPHITE=${GRAPHITE:-10.10.5.244}

if [ ! -n "$CLUSTER" ]; then
    if [ ! -n "$JOB_NAME" ]; then
        echo "JOB_NAME is not set"
        return 1
    fi

    if [ ! -n "$BUILD_NUMBER" ]; then
        echo "BUILD_NUMBER is not set"
        return 1
    fi

    cluster="$JOB_NAME-$BUILD_NUMBER"
    echo "CLUSTER is not set. Defaulting to $cluster"
else
    cluster="$CLUSTER"
fi

cloudXccli() {
    cmd="gcloud compute ssh $cluster-1 -- \"/opt/xcalar/bin/xccli\""
    for arg in "$@"; do
        arg="${arg//\\/\\\\}"
        arg="${arg//\"/\\\"}"
        cmd="$cmd \"$arg\""
    done
    $cmd
}

stopXcalar() {
    $XLRINFRADIR/gce/gce-cluster-ssh.sh $cluster "sudo systemctl stop xcalar.service"
}

restartXcalar() {
    set +e
    stopXcalar
    $XLRINFRADIR/gce/gce-cluster-ssh.sh $cluster "sudo systemctl start xcalar.service"
    for ii in $(seq 1 $NUM_INSTANCES ) ; do
        host="${cluster}-${ii}"
        gcloud compute ssh $host --zone us-central1-f -- "sudo /opt/xcalar/bin/xcalarctl status" 2>&1 | grep -q  "Usrnodes started"
        ret=$?
        numRetries=60
        try=0
        while [ $ret -ne 0 -a "$try" -lt "$numRetries" ]; do
            sleep 1s
            gcloud compute ssh $host --zone us-central1-f -- "sudo /opt/xcalar/bin/xcalarctl status" 2>&1 | grep -q "Usrnodes started"
            ret=$?
            try=$(( $try + 1 ))
        done
        if [ $ret -eq 0 ]; then
            echo "All nodes ready"
        else
            echo "Error while waiting for node $ii to come up"
            return 1
        fi
    done
    set -e
}

genSupport() {
    $XLRINFRADIR/gce/gce-cluster-ssh.sh $cluster "sudo /opt/xcalar/scripts/support-generate.sh"
}

funcstatsd() {
    local name="${1//::/_}"
    local status="$2"
    local gitsha="$3"
    if [ "$status" = "PASS" ]; then
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numPass:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.status:0|g" | nc -4 -w 5 -u $GRAPHITE 8125
    elif [ "$status" = "FAIL" ]; then
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.numFail:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${cluster//./_}.status:1|g" | nc -4 -w 5 -u $GRAPHITE 8125
    fi
}
