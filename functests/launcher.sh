#!/bin/bash
set -x

# This script starts up xcmonitor which starts up the usrnode
set +e

ulimit -c unlimited
ulimit -l unlimited

# Change defaults for your installation in the following file
if [ -r "${INSTALL_OUTPUT_DIR}/etc/default/xcalar" ]; then
    . $INSTALL_OUTPUT_DIR/etc/default/xcalar
fi

export XCE_CONFIG="${XCE_CONFIG:-/etc/xcalar/default.cfg}"
export XLRDIR="${XLRDIR:-/opt/xcalar}"
export XLRGUIDIR="${XLRGUIDIR:-/opt/xcalar/xcalar-gui}"
export XCE_PUBSIGNKEYFILE="${XCE_PUBSIGNKEYFILE:-/etc/xcalar/EcdsaPub.key}"

LIBHDFS3_CONF="${LIBHDFS3_CONF:-/etc/xcalar/hdfs-client.xml}"
PATH="$XLRDIR/bin:$PATH"
XCE_LICENSEDIR="${XCE_LICENSEDIR:-`pwd`/src/data}"
XCE_LOGDIR="$(awk -F'=' '/^Constants.XcalarLogCompletePath/{print $2}' $XCE_CONFIG)"
CGROUPS_ENABLED=$(grep '^Constants.Cgroups' "$XCE_CONFIG" | tail -1 | cut -d '=' -f 2)
CGROUP_XCALAR_XCE=xcalar_xce_${USER}
CGROUP_XCALAR_MW=xcalar_middleware_${USER}
XCE_LOGDIR="${XCE_LOGDIR:-/var/log/xcalar}"
export MALLOC_CHECK_=2

export XCE_CONFIG XCE_LOGDIR XLRDIR LIBHDFS3_CONF PATH XCE_LICENSEDIR

mkdir -p $INSTALL_OUTPUT_DIR/var/run/xcalar

oldpids="$(cat ${INSTALL_OUTPUT_DIR}/var/run/xcalar/*.pid 2>/dev/null)"
if test -n "$oldpids"; then
    kill -- $oldpids 2>/dev/null || true
    sleep 5
    kill -9 $oldpids 2>/dev/null || true
    rm -f $INSTALL_OUTPUT_DIR/var/run/xcalar/*.pid
fi

killall xcmgmtd xcmonitor usrnode childnode &>/dev/null || true
# Give enough time for processes to go away and free up the tcp ports
sleep 30
find /var/opt/xcalar -type f -not -path '/var/opt/xcalar/support/*' -delete
find /dev/shm -name "xcalar-*" -delete

# ENG-9870 possible race condition restarting usrnode, cannot bind socket/port
# adding netstat before restarting the cluster
netstat -anop

joinBy() { local IFS="$1"; shift; echo "$*"; }

if [ "$CGROUPS_ENABLED" != "false" ]; then
    childnode_paths=("/sys/fs/cgroup/cpu,cpuacct/xcalar.slice/xcalar-usrnode.service" "/sys/fs/cgroup/memory/xcalar.slice/xcalar-usrnode.service")

    export XCE_CHILDNODE_PATHS=$(joinBy ':' "${childnode_paths[@]}")
    export XCE_CGROUP_CONTROLLER_MAP="memory%/sys/fs/cgroup/memory:cpu%/sys/fs/cgroup/cpu,cpuacct:cpuacct%/sys/fs/cgroup/cpu,cpuacct"
    export XCE_CGROUP_CONTROLLERS="memory cpu cpuacct"
    export XCE_CGROUP_UNIT_PATH="xcalar.slice/xcalar-usrnode.service"
    export XCE_CHILDNODE_SCOPES="sys_xpus-sched0 sys_xpus-sched1 sys_xpus-sched2 usr_xpus-sched0 usr_xpus-sched1 usr_xpus-sched2"

    MY_UID=$(id -u)
    MY_GID=$(id -g)

    for node_path in "${childnode_paths[@]}"; do
        sudo /bin/chown -R "$MY_UID":"$MY_GID" "$node_path"
    done
fi

if [ "$CGROUPS_ENABLED" != "false" ]; then
    cgexec -g cpu,cpuacct,memory:${CGROUP_XCALAR_MW} --sticky $XLRDIR/bin/xcmgmtd $XCE_CONFIG >> $XCE_LOGDIR/xcmgmtd.out 2>&1 </dev/null &
else
    $XLRDIR/bin/xcmgmtd $XCE_CONFIG >> $XCE_LOGDIR/xcmgmtd.out 2>&1 </dev/null &
fi

pid=$!
echo $pid > $INSTALL_OUTPUT_DIR/var/run/xcalar/xcmgmtd.pid

NumNodes=$(awk -F= '/^Node.NumNodes/{print $2}' $XCE_CONFIG)

for ii in $(seq 0 $(( $NumNodes - 1 ))); do
    monitorLog=$XCE_LOGDIR/xcmonitor.${ii}.out
    # memAllocator = 1(jemalloc) and memAllocator = 2(guardrails)
    if [ $1 -eq 1 ]; then
        MALLOC_CONF=tcache:false,junk:true $XLRDIR/bin/xcmonitor -n $ii -m $NumNodes -c $XCE_CONFIG -k $XCE_LICENSEDIR/XcalarLic.key > $monitorLog 2>&1 &
    elif [ $1 -eq 2 ]; then
        grlibpath="`pwd`/xcalar-infra/GuardRails/libguardrails.so.0.0"
        if [ "$CGROUPS_ENABLED" != "false" ]; then
            cgexec -g cpu,cpuacct,memory:${CGROUP_XCALAR_XCE} --sticky $XLRDIR/bin/xcmonitor -n $ii -m $NumNodes -c $XCE_CONFIG -g "$grlibpath" -k $XCE_LICENSEDIR/XcalarLic.key > $monitorLog 2>&1 &
        else
            $XLRDIR/bin/xcmonitor -n $ii -m $NumNodes -c $XCE_CONFIG -g "$grlibpath" -k $XCE_LICENSEDIR/XcalarLic.key > $monitorLog 2>&1 &
        fi
    else
        if [ "$CGROUPS_ENABLED" != "false" ]; then
            cgexec -g cpu,cpuacct,memory:${CGROUP_XCALAR_XCE} --sticky $XLRDIR/bin/xcmonitor -n $ii -m $NumNodes -c $XCE_CONFIG -k $XCE_LICENSEDIR/XcalarLic.key > $monitorLog 2>&1 &
        else
            $XLRDIR/bin/xcmonitor -n $ii -m $NumNodes -c $XCE_CONFIG -k $XCE_LICENSEDIR/XcalarLic.key > $monitorLog 2>&1 &
        fi
    fi
    pid=$!
    echo $pid > $INSTALL_OUTPUT_DIR/var/run/xcalar/xcmonitor.${ii}.pid
done

backendUp="false"
sleepTime=10
for ii in $(seq 60); do
    if xccli -c version 2>&1 | grep -q 'Backend Version:'; then
        backendUp="true"
        break
    fi
    sleep $sleepTime
done

if [ "$backendUp" = "false" ]; then
    echo "Backend not up after " $(($sleepTime * $ii)) " seconds"
    exit 1
fi

exit 0
