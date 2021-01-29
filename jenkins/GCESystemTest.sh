export XLRDIR=`pwd`
export PATH="$XLRDIR/bin:$HOME/google-cloud-sdk/bin:$PATH"

if $BUILD; then
    build clean
    build config
    build
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


cluster=`echo $JOB_NAME-$BUILD_NUMBER | tr A-Z a-z`

# Delete the old GCE instance(s), just in case it's (they're) still hanging around
xcalar-infra/gce/gce-cluster-delete.sh $cluster || true

sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100

# Create new GCE instance(s)
ret=`xcalar-infra/gce/gce-cluster-xcmonitor.sh $installer $NUM_INSTANCES $cluster`

if [ "$NOTPREEMPTIBLE" != "1" ]; then
    ips=($(awk '/RUNNING/ {print $6":18552"}' <<< "$ret"))
else
    ips=($(awk '/RUNNING/ {print $5":18552"}' <<< "$ret"))
fi

echo "$ips"

stopXcalar() {
    xcalar-infra/gce/gce-cluster-ssh.sh $cluster "sudo /opt/xcalar/bin/xcalarctl stop-supervisor"
    # Wait for the usrnode to shutdown
    host="${cluster}-1"
    gcloud compute ssh $host --zone us-central1-f -- "sudo /opt/xcalar/bin/xcalarctl status" 2>&1 | grep -q  "Usrnodes not started"
    ret=$?
    numRetries=60
    try=0
    while [ $ret -ne 0 -a "$try" -lt "$numRetries" ]; do
        sleep 1s
        gcloud compute ssh $host --zone us-central1-f -- "sudo /opt/xcalar/bin/xcalarctl status" 2>&1 | grep -q  "Usrnodes not started"
        ret=$?
        try=$(( $try + 1 ))
    done
    if [ $ret -eq 0 ]; then
        echo "All nodes stopped"
    else
        echo "Error while waiting for nodes to stop"
        return 1
    fi
}

restartXcalar() {
    set +e
    stopXcalar
    # xcalar-infra/gce/gce-cluster-ssh.sh $cluster "sudo service xcalar start"
    # Start xcmonitor which will start the usrnodes once all the xcmonitors form a cluster
    xcalar-infra/gce/gce-cluster-ssh.sh $cluster "sudo /opt/xcalar/bin/xcalarctl start"
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
    xcalar-infra/gce/gce-cluster-ssh.sh $cluster -- "sudo bash -x /opt/xcalar/scripts/support-generate.sh"
}

startupDone() {
    for node in `gcloud compute instances list | grep $cluster | cut -d \  -f 1`; do
        gcloud compute ssh $node -- "sudo journalctl -r" | grep -q "Startup finished";
        ret=$?
        if [ "$ret" != "0" ]; then
            return $ret
        fi
    done
    return 0
}

try=0
while ! startupDone ; do
    echo "Waited $try seconds for Xcalar to come up"
    sleep 1
    try=$(( $try + 1 ))
    if [[ $try -gt 200 ]]; then
            if $LEAVE_ON_FAILURE; then
                    echo "As requested, cluster will not be cleaned up."
                    echo "Run 'xcalar-infra/gce/gce-cluster-delete.sh ${cluster}' once finished."
        else
            xcalar-infra/gce/gce-cluster-delete.sh $cluster || true
            if [ "$cluster" != "" ]; then
                gcloud compute ssh graphite -- "sudo rm -rf /srv/grafana-graphite/data/whisper/collectd/$cluster"
            fi
            fi
        exit 1
     fi
done

xcalar-infra/gce/gce-cluster-ssh.sh $cluster -- "echo Constants.SendSupportBundle=true | sudo tee -a /etc/xcalar/default.cfg"

restartXcalar

# remove when bug 2670 fixed
hosts=$( IFS=$','; echo "${ips[*]}" )

xcalar-infra/gce/gce-cluster-ssh.sh $cluster -- "sudo pip install google-cloud-storage"
xcalar-infra/gce/gce-cluster-ssh.sh $cluster -- "sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100"

source $XLRDIR/doc/env/xc_aliases

xcEnvEnter

set +e
python "$XLRDIR/src/bin/tests/systemTests/runTest.py" -n 1 -i ${ips[0]} -t gce52Config -w --serial
ret="$?"

if [ $ret -eq 0 ]; then
        xcalar-infra/gce/gce-cluster-delete.sh $cluster || true
    if [ "$cluster" != "" ]; then
        gcloud compute ssh graphite -- "sudo rm -rf /srv/grafana-graphite/data/whisper/collectd/$cluster"
    fi
else
    genSupport
    echo "One or more tests failed"
        if [ "$LEAVE_ON_FAILURE" = "true" ]; then
                echo "As requested, cluster will not be cleaned up."
                echo "Run 'xcalar-infra/gce/gce-cluster-delete.sh ${cluster}' once finished."
        else
                xcalar-infra/gce/gce-cluster-delete.sh $cluster || true
        fi
fi

exit $ret
