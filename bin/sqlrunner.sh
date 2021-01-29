#!/bin/bash

set -e

myName=$(basename $0)

XLRINFRADIR=${XLRINFRADIR-$HOME/xcalar-infra}
PERSIST_COVERAGE_ROOT="${PERSIST_COVERAGE_ROOT:-/netstore/qa/coverage}"
RUN_COVERAGE="${RUN_COVERAGE:-false}"
export CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-${XLRINFRADIR}/misc/sqlrunner/template.cfg}"

optClusterName=""
optKeep=false
optUseExisting=false
optXcalarImage=""
optNumNodes=1
optRemoteXlrDir="/opt/xcalar"
optRemoteXlrRoot="/mnt/xcalar"
optRemotePwd="/tmp/test_jdbc"
optInstanceType="n1-standard-4"
optNoPreempt=0
optSetupOnly=false
optResultsPath="."
optTimeoutSec=$(( 10 * 60 ))
optEnableSpark=false
optEnableAnswer=false
optBucket="sqlscaletest"
optHours=0
optSupportBundle=false
optTcpdump=false
SPARK_DOCKER_DIR="$XLRDIR/docker/spark/master"

usage()
{
    cat << EOF
    Runs randomized, multi-user SQL tests at scale in GCE.  Handles all
    configuration, cluster management and installation.

    Requires paswordless GCE ssh (see Xcalar/GCE wiki), eg:
        eval \`ssh-agent\`
        ssh-add -t0 ~/.ssh/google_compute_engine

    Example invocation:
        $myName -c ecohen-sqlrunner -I n1-standard-8 -n 3 -i /netstore/builds/byJob/BuildTrunk/2707/prod/xcalar-2.0.0-2707-installer -N -d -- -w 1 -t test_tpch -s 1031 -U test-admin@xcalar.com -P welcome1
    All options following "--" are passed as-is to test_jdbc.py.

    Usage: $myName <options> -- <test_jdbc options>
        -c <name>       GCE cluster name
        -d <tcpdump>    Capture packets from some node 0 ports to pcap file (on failure)
        -i <image>      Path to Xcalar installer image
        -I <type>       GCE instance type (eg n1-standard-8)
        -k              Leave cluster running on exit
        -l <license>    Path to Xcalar license
        -n <nodes>      Number of nodes in cluster
        -N              Disable GCE preemption
        -p <wdpath>     Remote working directory
        -r <results>    Directory to store perf results
        -s              Pull support bundle on failure
        -S              Set up and configure cluster but skip SQL tests
        -t <timeout>    Cluster startup timeout (seconds)
        -T <hours>      Iterate test for at least this many hours
        -u              Use an existing cluster instead of creating one
        -x <instpath>   Path to Xcalar install directory on cluster
        -X <xlrpath>    Path to Xcalar root on cluster
        -b <bucket>     Gcloud storage bucket
        -d              Enable spark
        -A              Enable docker container, and generate spark answer files.
EOF
}

while getopts "c:di:I:kn:Npr:sSt:T:ux:X:b:dA" opt; do
  case $opt in
      c) optClusterName="$OPTARG";;
      d) optTcpdump=true;;
      i) optXcalarImage="$OPTARG";;
      I) optInstanceType="$OPTARG";;
      k) optKeep=true;;
      n) optNumNodes="$OPTARG";;
      N) optNoPreempt=1;;
      p) optRemotePwd="$OPTARG";;
      r) optResultsPath="$OPTARG";;
      s) optSupportBundle=true;;
      S) optSetupOnly=true;;
      t) optTimeoutSec="$OPTARG";;
      T) optHours="$OPTARG";;
      u) optUseExisting=true;;
      x) optRemoteXlrDir="$OPTARG";;
      X) optRemoteXlrRoot="$OPTARG";;
      b) optBucket="$OPTARG";;
      d) optEnableSpark=true;;
      A) optEnableAnswer=true;;
      --) break;; # Pass all following to test_jdbc
      *) usage; exit 0;;
  esac
done

shift $(($OPTIND - 1))
optsTestJdbc="$@"

if [[ -z "$optClusterName" ]]
then
    echo "-c <clustername> required"
    exit 1
fi

# GCE requires lower case names
optClusterName=$(echo "$optClusterName" | tr '[:upper:]' '[:lower:]')
clusterLeadName="$optClusterName-1"
SPARKRESULTPATH="/tmp/$optClusterName/"

if [ "$IS_RC" = "true" ]; then
    prodLicense=`cat $XLRDIR/src/data/XcalarLic.key.prod | gzip | base64 -w0`
    export XCE_LICENSE="${XCE_LICENSE:-$prodLicense}"
else
    devLicense=`cat $XLRDIR/src/data/XcalarLic.key | gzip | base64 -w0`
    export XCE_LICENSE="${XCE_LICENSE:-$devLicense}"
fi

rcmdNode() {
    local nodeNum="$1"
    shift
    args="$@"
    #have to ssh cluster as user "xcalar"
    gcloud compute ssh "xcalar@$optClusterName-$nodeNum" --command "$args"
}

rcmd() {
    rcmdNode 1 "$@"
}

rcmdAll() {
    for nodeNum in $(seq 1 $optNumNodes)
    do
        # XXX: run in parallel
        rcmdNode $nodeNum "$@"
    done
}

gscpToNode() {
    local nodeNum="$1"
    local src="$2"
    local dst="$3"

    #running the script as user "Jenkins"
    #ssh to the remote cluster as user "xcalar"
    eval gcloud compute scp --recurse "$src" "xcalar@$optClusterName-$nodeNum:$dst"
}

gscpTo() {
    local src="$1"
    local dst="$2"
    gscpToNode 1 "$src" "$dst"
}

gscpToAll() {
    local src="$1"
    local dst="$2"
    for nodeNum in $(seq 1 $optNumNodes)
    do
        # XXX: run in parallel
        gscpToNode $nodeNum "$src" "$dst"
    done
}

gscpFromNode() {
    local nodeNum="$1"
    local src="$2"
    local dst="$3"
    #ssh to remote cluster as user "xcalar"
    #copy file to /home/jenkins/...
    gcloud compute scp --recurse "xcalar@$optClusterName-$nodeNum:$src" "$dst"
}

gscpFrom() {
    local src="$1"
    local dst="$2"
    gscpFromNode 1 "$src" "$dst"
}

gscpFromAll() {
    local src="$1"
    local dst="$2"
    for nodeNum in $(seq 1 $optNumNodes)
    do
        gscpFromNode $nodeNum "$src" "$dst"
    done
}

getNodeIp() {
    nodeNum=$1
    gcloud compute instances describe "$optClusterName-$nodeNum" \
        --format='value[](networkInterfaces.networkIP)' \
        | python -c 'import sys; print(eval(sys.stdin.readline())[0]);'
}

getSparkIp() {
    gcloud compute instances describe "$optClusterName-spark-m" \
        --format='value[](networkInterfaces.accessConfigs.natIP)' \
        | echo $(python -c 'import sys; print(eval(sys.stdin.readline())[0]);')
}

waitCmd() {
    local cmd="$1"
    local to="$2"
    local ct=1

    while ! eval $cmd
    do
        sleep 1
        local ct=$(( $ct + 1 ))
        echo "Waited $ct seconds for: $cmd"
        if [[ $ct -gt $to ]]
        then
            echo "Timed out waiting for: $cmd"
            exit 1
        fi
    done
}

createCluster() {
    if [[ ! -f "$optXcalarImage" ]]
    then
        echo "    -i <installerImagePath> required"
        echo "    Example: /netstore/builds/byJob/BuildStable/79/prod/xcalar-1.4.1-2413-installer"
        exit 1
    fi

    echo "Creating $optNumNodes node cluster $optClusterName"
    IMAGE="${IMAGE:-rhel-7}" INSTANCE_TYPE=$optInstanceType NOTPREEMPTIBLE=$optNoPreempt \
        $XLRINFRADIR/gce/gce-cluster.sh "$optXcalarImage" $optNumNodes $optClusterName
    echo "Waiting for Xcalar start on $optNumNodes node cluster $optClusterName"

    waitCmd "rcmd $optRemoteXlrDir/bin/xccli -c version > /dev/null" $optTimeoutSec
    if $optEnableSpark
    then
        $XLRINFRADIR/bin/gce-dataproc.sh -c "$optClusterName-spark" -m $optInstanceType -n $(($optNumNodes - 1)) \
            -w $optInstanceType -b $optBucket -f "$optClusterName-port"
        SPARK_IP=$(getSparkIp)
    fi
}

installDeps() {
    rcmd sudo yum install -y tmux nc gcc gcc-c++ tcpdump pbzip2 java-1.8.0-openjdk-headless
    rcmd sudo "$optRemoteXlrDir/bin/python3" -m pip install "gnureadline==6.3.8" "multiset==2.1.1" "JPype1==0.6.3" "JayDeBeApi==1.1.1"
    # XXX: Fix in test_jdbc
    local imdTestDir="/opt/xcalar/src/sqldf/tests/IMDTest/"
    rcmd mkdir -p "$optRemotePwd"
    rcmd mkdir -p "$optRemotePwd/result/"
    rcmd sudo mkdir -p "$imdTestDir"
    rcmd sudo chmod a+rwx "$imdTestDir"
    gscpTo "$XLRDIR/src/sqldf/tests/*.py" "$optRemotePwd"
    gscpTo "$XLRGUIDIR/assets/test/json/*.json" "$optRemotePwd"
    gscpTo "$XLRDIR/src/sqldf/tests/IMDTest/*.json" "$imdTestDir"
    gscpTo "$XLRDIR/src/sqldf/tests/IMDTest/loadData.py" "$imdTestDir"

    gscpTo "$XLRINFRADIR/misc/sqlrunner/jodbc.xml" /tmp
    if [ "$RUN_COVERAGE" = "true" ]; then
        gscpTo "$XLRINFRADIR/misc/sqlrunner/supervisor_coverage.conf" /tmp/supervisor.conf
    else
        gscpTo "$XLRINFRADIR/misc/sqlrunner/supervisor.conf" /tmp
    fi
    gscpToAll "$XLRINFRADIR/misc/sqlrunner/LocalUtils.sh" /tmp
    #running the command on remote cluster as user "xcalar"
    rcmdAll echo "source /tmp/LocalUtils.sh >> ~/.bashrc"

    if $optEnableAnswer
    then
    gcloud compute scp ${SPARKRESULTPATH}result*.json "$clusterLeadName:$optRemotePwd/result/"
    rm -rf "$SPARKRESULTPATH"
    fi

    rcmd sudo mv "/tmp/jodbc.xml" "$optRemoteXlrRoot/config"
    rcmd sudo mv "/tmp/supervisor.conf" "/etc/xcalar/"
    rcmd sudo /opt/xcalar/bin/supervisorctl -s unix:///var/tmp/xcalar-root/supervisor.sock reread || true
    rcmd sudo /opt/xcalar/bin/supervisorctl -s unix:///var/tmp/xcalar-root/supervisor.sock reload || true
    rcmd sudo /opt/xcalar/bin/supervisorctl -s unix:///var/tmp/xcalar-root/supervisor.sock restart xcalar:sqldf || true

    if $optTcpdump
    then
        rcmd 'sudo nohup tcpdump -W 2 -C 500 -ni any -w $(hostname).pcap port 9090 or port 12124 or port 10000 >tcpdump-stdout.out 2>tcpdump-stderr.out < /dev/null &'
    fi

    if $optEnableSpark
    then
        waitCmd "rcmd 'nc $SPARK_IP 10000 </dev/null 2>/dev/null'" $optTimeoutSec
    fi
    waitCmd "rcmd 'nc localhost 10000 </dev/null 2>/dev/null'" $optTimeoutSec
}

dumpStats() {
    rcmdAll dumpNodeOSStats
    rcmd /opt/xcalar/bin/xccli -c top
}

generateAnswer(){
    (cd "$SPARK_DOCKER_DIR" && make rm && make run)
    mkdir -p $SPARKRESULTPATH
    local SPARK_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' spark-master-jdbc)
    waitCmd "nc $SPARK_IP 10000 </dev/null 2>/dev/null" $optTimeoutSec
    $XLRDIR/src/sqldf/tests/test_jdbc.py \
     -p "$XLRGUIDIR/assets/test/json/"  -S $SPARK_IP $optsTestJdbc -w 1 -P admin -U admin --ignore-xcalar --spark_result "$SPARKRESULTPATH/result"
}

runTest() {
    local testIter="$1"

    echo "######## Starting iteration $testIter ########"

    if $optEnableSpark
    then
        local results_spark="$optRemotePwd/$optClusterName-${optNumNodes}nodes-$optInstanceType-$testIter-spark"
        rcmd "XLRDIR=$optRemoteXlrDir" "$optRemoteXlrDir/bin/python3" "$optRemotePwd/test_jdbc.py" \
            -p "$optRemotePwd" -o $results_spark -n "$optNumNodes,$optInstanceType" -S $SPARK_IP --bucket "gs://$optBucket/" $optsTestJdbc --ignore-xcalar
        gscpFrom "${results_spark}*.json" "$optResultsPath"
    fi

    local results_xcalar="$optRemotePwd/$optClusterName-${optNumNodes}nodes-$optInstanceType-$testIter-xcalar"
    rcmd "XLRDIR=$optRemoteXlrDir" "$optRemoteXlrDir/bin/python3" "$optRemotePwd/test_jdbc.py" \
        -p "$optRemotePwd" -o $results_xcalar -n "$optNumNodes,$optInstanceType" $optsTestJdbc --spark_file_verify "$optRemotePwd/result/result"

    # IMD test doesn't generate a perf file
    gscpFrom "${results_xcalar}*.json" "$optResultsPath" || true

    echo "######## Ending iteration $testIter ########"
}

collectCoverage() {
    # Collect any coverage files

    echo "COVERAGE collectCoverage called"

    # Create persistent storage for our coverage data
    coverageRoot=${PERSIST_COVERAGE_ROOT}/${JOB_NAME}/${BUILD_NUMBER}
    mkdir -p "$coverageRoot"
    echo "COVERAGE coverageRoot: $coverageRoot"

    # Copy off the coverage rawprof files
    for nodeNum in $(seq 1 $optNumNodes)
    do
        echo "COVERAGE processing node $nodeNum"

        src_dir="/var/opt/xcalar/coverage/*"
        dst_dir="${coverageRoot}/node_${nodeNum}/rawprof"
        mkdir -p $dst_dir
        gscpFromNode $nodeNum ${src_dir} ${dst_dir}
    done

    # Get a copy of the usrnode binary
    src_bin="/opt/xcalar/bin/usrnode"
    dst_dir="${coverageRoot}/bin"
    mkdir -p $dst_dir
    gscpFrom ${src_bin} ${dst_dir}

    chmod -R o+rx "$coverageRoot" # Play nice with others :)
}

exitHandler() {
    # Preserve the value for use here, but note bash returns the $? value from prior to exit handler invocation.
    retval=$?

    set +e # allow exit handler to proceed with errors

    if $optSupportBundle && [[ $retval -ne 0 ]]
    then
        rcmdAll sudo /opt/xcalar/scripts/support-generate.sh
        # support is on shared storage, so no need for copy from all
        gscpFrom /mnt/xcalar/support $optResultsPath
    else
        echo "NOT collecting support bundle (retval: $retval, -s option: $optSupportBundle)"
    fi

    if $optTcpdump && [[ $retval -ne 0 ]] # Only download pcap file on failure
    then
        rcmd 'sudo pkill -SIGTERM tcpdump && sleep 5 && pbzip2 *.pcap*'
        gscpFrom "*.bz2" "$optResultsPath"
    fi

    if [ "$RUN_COVERAGE" = "true" ]; then
        echo "RUN_COVERAGE is TRUE"
        # Have to shut down the cluster in order to collect coverage.
        $XLRINFRADIR/gce/gce-cluster-stop.sh $optNumNodes $optClusterName
        collectCoverage
    else
        echo "RUN_COVERAGE is FALSE"
    fi

    if ! $optKeep
    then

        $XLRINFRADIR/gce/gce-cluster-delete.sh --all-disks $optClusterName
        if $optEnableSpark
        then
            $XLRINFRADIR/bin/gce-dataproc-delete.sh -c "$optClusterName-spark" -f "$optClusterName-port"
        fi
    else
        # Need to start it back up again...
        if [ "$RUN_COVERAGE" = "true" ]; then
            $XLRINFRADIR/gce/gce-cluster-start.sh $optNumNodes $optClusterName
        fi
    fi

    echo "Test artifacts left in $optResultsPath"
    rm -rf "$SPARKRESULTPATH"
}

trap exitHandler EXIT

if $optEnableAnswer
then
    generateAnswer
fi

if ! $optUseExisting
then
    createCluster
fi

installDeps

if ! $optSetupOnly
then
    testIter=0
    endTime=$(($(date +%s) + optHours * 60 * 60))

    dumpStats
    runTest $testIter
    dumpStats
    testIter=$((testIter + 1))

    while [[ "$(date +%s)" -lt "$endTime" ]]
    do
        echo "Current time: $(date +%s), End time: $endTime, remaining: $((endTime - $(date +%s)))"
        runTest $testIter
        dumpStats
        testIter=$((testIter + 1))
    done

fi
