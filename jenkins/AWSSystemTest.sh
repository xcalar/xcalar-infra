bash /netstore/users/jenkins/slave/setup.sh

export XLRDIR=`pwd`
export PATH=$PATH:"$XLRDIR/bin"
export TAP="AllTests.tap"

sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100

source $XLRDIR/doc/env/xc_aliases
xcEnvEnter

if $BUILD; then
    cmBuild clean
    cmBuild config debug
    cmBuild qa
fi

if [ -n "$INSTALLER_PATH" ]; then
    installer=$INSTALLER_PATH
else
    export XLRGUIDIR=`pwd`/xcalar-gui
    cd docker
    make
    cd -
    cbuild el7-build prod
    cbuild el7-build package
    installer=`find build -type f -name 'xcalar-*-installer'`
fi

echo "Host *.us-west-2.compute.amazonaws.com
    User ec2-user
    IdentityFile "$AWS_PEM"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR" > ~/.ssh/config

chmod 0600 ~/.ssh/config

if [ "$CLUSTER" = "" ]; then
    cluster=`echo $JOB_NAME-$BUILD_NUMBER | tr A-Z a-z`
    xcalar-infra/aws/aws-cloudformation.sh $INSTALLER_PATH $NUM_INSTANCES $cluster
    ret=$?
    if [ $ret -ne 0 ]; then
        if [ "$LEAVE_ON_FAILURE" = "true" ]; then
            echo "As requested, cluster will not be cleaned up."
            echo "Run 'xcalar-infra/aws/aws-cloudformation-delete.sh ${cluster}' once finished."
        else
            xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
        fi
        exit 1
    fi
else
    cluster=$CLUSTER
fi

sleep 120

cloudXccli() {
    cmd="xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster singleNode \"/opt/xcalar/bin/xccli\""
    for arg in "$@"; do
        arg="${arg//\\/\\\\}"
        arg="${arg//\"/\\\"}"
        cmd="$cmd \"$arg\""
    done
    $cmd
}

startupDone() {
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo journalctl -r | grep -q 'Startup finished'"
    ret=$?
    if [ "$ret" != "0" ]; then
        return $ret
    fi
    return 0
}

waitForUsrnodes() {
    set +e

    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo /opt/xcalar/bin/xcalarctl status 2>&1 | grep -q 'Usrnodes started'"
    ret=$?
    numRetries=180
    try=0
    while [ $ret -ne 0 -a "$try" -lt "$numRetries" ]; do
        sleep 1s
        xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo /opt/xcalar/bin/xcalarctl status 2>&1 | grep -q 'Usrnodes started'"
        ret=$?
        try=$(( $try + 1 ))
    done

    if [ $ret -eq 0 ]; then
        echo "All nodes ready"
        return 0
    else
        echo "Error while waiting for nodes to come up"
        if [ "$LEAVE_ON_FAILURE" = "true" ]; then
            echo "As requested, cluster will not be cleaned up."
            echo "Run 'xcalar-infra/aws/aws-cloudformation-delete.sh ${cluster}' once finished."
        else
            xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
        fi
        return 1
    fi

    set +e

}

stopXcalar() {
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "sudo /opt/xcalar/bin/xcalarctl stop-supervisor"
}

restartXcalar() {
    set +e

    stopXcalar

    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "echo Constants.SendSupportBundle=true | sudo tee -a /etc/xcalar/default.cfg"

    sleep 60

    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "sudo service xcalar start"

    set -e
}

genSupport() {
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "sudo /opt/xcalar/scripts/support-generate.sh"
}

mountSsd() {
    # XXX check if /dev/xvdb is present
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo cat /sys/block/xvdb/queue/discard_max_bytes"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo mkfs.ext4 -E nodiscard /dev/xvdb"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo chown -R ec2-user:ec2-user /ssd"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "echo /dev/xvdb /ssd ext4 defaults,nofail,noatime,discard 0 2 | sudo tee -a /etc/fstab"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo mkdir /ssd"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo mount /ssd"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo mkdir -p /ssd/xdbser"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "sudo chmod -R 777 /ssd"
    xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "runClusterCmd" "echo Constants.XdbLocalSerDesPath=/ssd/xdbser | sudo tee -a /etc/xcalar/default.cfg"
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

try=0
while ! startupDone ; do
    echo "Waited $try seconds for Xcalar to come up"
    sleep 2
    try=$(( $try + 1 ))
    if [ "$try" -gt 600 ]; then
        echo "Timeout while waiting for Xcalar to come up"
        if [ "$LEAVE_ON_FAILURE" = "true" ]; then
            echo "As requested, cluster will not be cleaned up."
            echo "Run 'xcalar-infra/aws/aws-cloudformation-delete.sh ${cluster}' once finished."
        else
            xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
        fi
        exit 1
    fi
done

waitForUsrnodes

mountSsd

restartXcalar

waitForUsrnodes

xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100"

gitsha=`cloudXccli -c "version" | head -n2 | cut -d\  -f3 | cut -d- -f5`
host=$(xcalar-infra/aws/aws-cloudformation-ssh.sh $cluster "host")
port=18552

echo "1..$NUM_ITERATIONS" | tee "$TAP"
set +e
for ii in `seq 1 $NUM_ITERATIONS`; do
    Test="$SYSTEM_TEST_CONFIG-$NUM_USERS"
    python "$XLRDIR/src/bin/tests/systemTests/runTest.py" -n $NUM_USERS -i $host:$port -t $SYSTEM_TEST_CONFIG -w --serial
    ret="$?"
    if [ "$ret" = "0" ]; then
        echo "Passed '$Test' at `date`"
        funcstatsd "$Test" "PASS" "$gitsha"
        echo "ok ${ii} - $Test-$ii"  | tee -a $TAP
    else
        genSupport
        funcstatsd "$Test" "FAIL" "$gitsha"
        echo "not ok ${ii} - $Test-$ii" | tee -a $TAP
        if [ "$LEAVE_ON_FAILURE" = "true" ]; then
            echo "As requested, cluster will not be cleaned up."
            echo "Run 'xcalar-infra/aws/aws-cloudformation-delete.sh ${cluster}' once finished."
        else
            xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
        fi
        exit $ret
    fi
done

xcalar-infra/aws/aws-cloudformation-ssh.sh "$cluster" runClusterCmd "/opt/xcalar/bin/xccli -c 'stats 0'"
xcalar-infra/aws/aws-cloudformation-ssh.sh "$cluster" runClusterCmd "/opt/xcalar/bin/xccli -c 'stats 1'"
set -e

if [ $ret -eq 0 ]; then
    xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
else
    if [ "$LEAVE_ON_FAILURE" = "true" ]; then
        echo "As requested, cluster will not be cleaned up."
        echo "Run 'xcalar-infra/aws/aws-cloudformation-delete.sh ${cluster}' once finished."
    else
        xcalar-infra/aws/aws-cloudformation-delete.sh $cluster || true
    fi
fi

sudo sysctl -w net.ipv4.tcp_keepalive_time=7200 net.ipv4.tcp_keepalive_intvl=75 net.ipv4.tcp_keepalive_probes=9

rm -rf ~/.ssh/config

exit $ret
