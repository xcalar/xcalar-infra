#!/bin/bash -x

touch /tmp/${JOB_NAME}_${BUILD_ID}_START_TIME

export INSTALL_OUTPUT_DIR=`pwd`/xcalar-install
export XLRDIR=$INSTALL_OUTPUT_DIR/opt/xcalar
export XLRGUIDIR=$XLRDIR/xcalar-gui
export XLRINFRADIR="${XLRINFRADIR:-$XLRDIR/xcalar-infra}"
export XCE_PUBSIGNKEYFILE=$INSTALL_OUTPUT_DIR/etc/xcalar/EcdsaPub.key

export PATH=$XLRDIR/bin:$PATH
export XCE_CONFIG=$INSTALL_OUTPUT_DIR/etc/xcalar/default.cfg
export XCE_USER=`id -un`
export XCE_GROUP=`id -gn`

TestsToRun=($TestCases)
TAP="AllTests.tap"
rm -f "$TAP"

restartXcalar() {
    xcalar-infra/functests/launcher.sh $memAllocator
}

genSupport() {
    miniDumpOn=`echo "$CONFIG_PARAMS" | grep "Constants.Minidump" | cut -d= -f 2`
    miniDumpOn=${miniDumpOn:-true}
    if [ "$miniDumpOn" = "true" ]; then
        sudo $XLRDIR/scripts/support-generate.sh
    else
        echo "support-generate.sh disabled because minidump is off. Check `pwd` for cores"
    fi
}

funcstatsd () {
    local name="${1//::/_}"
    local status="$2"
    local gitsha="$3"
    if [ "$status" = "PASS" ]; then
        echo "prod.functests.$TEST_TYPE.${hostname//./_}.${name}:0|g" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.numPass:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.status:0|g" | nc -4 -w 5 -u $GRAPHITE 8125
    elif [ "$status" = "FAIL" ]; then
        echo "prod.functests.$TEST_TYPE.${hostname//./_}.${name}:1|g" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.numFail:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
        echo "prod.tests.${gitsha}.functests.${name}.${hostname//./_}.status:1|g" | nc -4 -w 5 -u $GRAPHITE 8125
    fi
}

source ./bin/jenkins/jenkinsUtils.sh
trap "genBuildArtifacts" EXIT

# Build the source
source doc/env/xc_aliases

if [ $MemoryAllocator -eq 2 ]; then
    memAllocator=2
else
    memAllocator=0
fi

echo $GuardRailsArgs > grargs.txt

set +e
# Kill previous instances of xcalar processes
pkill -9 usrnode
pkill -9 childnode
pkill -9 xcmonitor
pkill -9 xcmgmtd
sleep 60

find /var/opt/xcalar -mindepth 1 -name support -prune -o -exec rm -rf {} +
set -e

sudo -E yum -y remove xcalar || true
rm -rf $INSTALL_OUTPUT_DIR
mkdir -p $INSTALL_OUTPUT_DIR

set +e
$INSTALLER_PATH -d $INSTALL_OUTPUT_DIR -v
rm $XCE_CONFIG
set -e


$XLRDIR/scripts/genConfig.sh $INSTALL_OUTPUT_DIR/etc/xcalar/template.cfg $XCE_CONFIG `hostname`
echo "$CONFIG_PARAMS" | tee -a $XCE_CONFIG

# Enable XEM
#echo "Constants.XcalarEnterpriseManagerEnabled=true" >> $XCE_CONFIG
#echo "Constants.XcalarClusterName=`hostname`" >> $XCE_CONFIG
#echo "XcalarEnterpriseManager.Host=xem-202-1.int.xcalar.com" >> $XCE_CONFIG
#echo "XcalarEnterpriseManager.Port=15000" >> $XCE_CONFIG
#echo "XcalarEnterpriseManager.IsVirtualXceCluster=true" >> $XCE_CONFIG

# Enable NoChildLDPreload so that childnodes do not inherit LD_PRELOAD from usrnode
echo "Constants.NoChildLDPreload=true" >> $XCE_CONFIG

sudo sed --in-place '/\dev\/shm/d' /etc/fstab
tmpFsSizeGb=`cat /proc/meminfo | grep MemTotal | awk '{ printf "%.0f\n", $2/1024/1024 }'`
let "tmpFsSizeGb = $tmpFsSizeGb * 95 / 100"

echo "none  /dev/shm    tmpfs   defaults,size=${tmpFsSizeGb%.*}G    0   0" | sudo tee -a /etc/fstab
sudo mount -o remount /dev/shm

# Increase the mmap map count for GuardRails to work
echo 100000000 | sudo tee /proc/sys/vm/max_map_count

# Build GuardRails
make -C xcalar-infra/GuardRails clean
make -C xcalar-infra/GuardRails deps
make -C xcalar-infra/GuardRails

# kill any previous test run instances
for pid in $(pidof -x FuncTestTrigger.sh); do
    if [ $pid != $$ ]; then
        kill -9 $pid
    fi
done

restartXcalar || true

if xccli -c version 2>&1 | grep -q 'Error'; then
    genSupport
    echo "Could not even start usrnodes after install"
    exit 1
fi

TMPDIR="${TMPDIR:-/tmp/`id -un`}/$JOB_NAME/functests"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

gitsha=`xccli -c "version" | head -n1 | cut -d\  -f3 | cut -d- -f5`
echo "GIT SHA: $gitsha"

AllTests=($(xccli -c 'functests list' | tail -n+2))
NumTests="${#TestsToRun[@]}"
ii=1
hostname=`hostname -f`

echo "prod.functests.$TEST_TYPE.${hostname//./_}.numberOfIters:$NUM_ITERATIONS|g" | nc -4 -w 5 -u $GRAPHITE 8125

NumNodes=$(awk -F= '/^Node.NumNodes/{print $2}' $XCE_CONFIG)

echo "1..$(( $NumTests * $NUM_ITERATIONS ))" | tee "$TAP"
set +e
for jj in `seq 1 $NUM_ITERATIONS`; do
    echo "Iteration $jj"
    echo "prod.functests.$TEST_TYPE.${hostname//./_}.currentIter:$jj|g" | nc -4 -w 5 -u $GRAPHITE 8125

    for Test in "${TestsToRun[@]}"; do
        anyfailed=0
        logfile="$TMPDIR/${hostname//./_}_${Test//::/_}.log"

        echo Running $Test on $hostname ...
        if xccli -c version 2>&1 | grep -q 'Error'; then
           genSupport
           restartXcalar || true
           if xccli -c version 2>&1 | grep -q 'Error'; then
                echo "Could not restart usrnodes after previous crash"
                exit 1
           fi
        fi

        if xccli -c "loglevelset Debug" 2>&1 | grep -q 'Error'; then
           genSupport
           restartXcalar || true
           if xccli -c version 2>&1 | grep -q 'Error'; then
                echo "Could not restart usrnodes after previous crash"
                exit 1
           fi
        fi

        echo "TESTCASE_START: $Test"
        time xccli -c "functests run --allNodes --testCase $Test" 2>&1 | tee "$logfile"
        echo "TESTCASE_END: $Test"

        rc=${PIPESTATUS[0]}
        if [ $rc -ne 0 ]; then
            anyfailed=1
        else
            if grep -q Error "$logfile"; then
                echo "Failed test output in $logfile at `date`"
                cat >&2 "$logfile"
                anyfailed=1
            fi
        fi

        # Print and check the stats from all the nodes for any xdb page leaks
        for nodeid in $(seq 0 $(( $NumNodes - 1 ))); do
            count=`xccli -c "stats $nodeid" | tee /dev/stderr | grep -e "xdb.pagekvbuf.bc    fastAllocs" -e "xdb.pagekvbuf.bc    fastFrees" | awk '{print $3}' | uniq  | wc -l`
            # count = 2 when fastAllocs and fastFrees differ
            # count = 1 when fastAllocs and fastFrees are same
            # count = 0 when xccli command fails(happens when usrnode crashed/sick)
            if [ $count -gt 1 ]; then
                # fastAllocs and fastFrees are different which means that there is a leak
                echo "Failed pagekvbuf leak test"
                # abort the usrnode to get a core file.
                # XXX: Commenting this out out for now to reduce noise.
                # pkill -9 usrnode
                # anyfailed=1
            fi
        done

        if [ $anyfailed -eq 1 ]; then
            genSupport

            # --------------------
            # Obsolete
            # --------------------
            # XXXrs - Cores etc. should be captured by genSupport
            # copy out the usrnode binary and retinas
            #now=$(date +"%Y%m%d_%H%M%S")
            #artdir="`pwd`/${now}_${BUILD_ID}"
            #mkdir -p $artdir
            #filepath="${artdir}/usrnode.$now"
            #retinapath="${artdir}/retina.$now"
            #exportpath="${artdir}/export.$now"
            #pubTablepath="${artdir}/pubTable.$now"
            ## XXXrs - Can race if multiple builds running on same node.
            ##         Blindly sweeps up any cores left-over from other
            ##         builds which failed to properly clean up. :/
            #mv core.childnode.* "$artdir"
            #mv core.usrnode.* "$artdir"
            #cp $XLRDIR/bin/usrnode "$filepath"
            #cp -r /var/opt/xcalar/dataflows/ "$retinapath"
            #cp -r /var/opt/xcalar/export/ "$exportpath"
            #cp -r /var/opt/xcalar/published/ "$pubTablepath"
            # mark the test as failed
            funcstatsd "$Test" "FAIL" "$gitsha"
            echo "not ok ${ii} - $Test" | tee -a $TAP
        else
            echo "Passed test at `date`"
            funcstatsd "$Test" "PASS" "$gitsha"
            echo "ok ${ii} - $Test"  | tee -a $TAP
        fi

        ii=$(( $ii + 1 ))
    done
done
# Shutdown the cluster
time xccli -c "shutdown" 2>&1 | tee "$logfile"

# Wait for cluster to shutdown
shutdownSuccessful="false"
for ii in `seq 1 60`; do
    pgrep usrnode
    ret=$?
    if [ "$ret" != "0" ]; then
        shutdownSuccessful="true"
        break
    fi
    sleep 1
done

if [ "$shutdownSuccessful" = "false" ]; then
    pkill -9 usrnode
    pkill -9 childnode
    pkill -9 xcmonitor
    pkill -9 xcmgmtd
fi
