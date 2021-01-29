#!/bin/bash -x

. $XLRDIR/bin/jenkins/auto-idl-review-sh-lib
source doc/env/xc_aliases

onExit() {
    local retval=$?
    set +e
    if [ $retval = 0 ]; then
        exit 0
    else
        genBuildArtifacts
        echo "Build artifacts copied to ${NETSTORE}/${JOB_NAME}/${BUILD_ID}"
    fi
    exit $retval
}


trap onExit EXIT SIGINT SIGTERM

if [ "$JOB_NAME" != "" ]; then
    # Tolerate slow cluster start.
    export TIME_TO_WAIT_FOR_CLUSTER_START="${TIME_TO_WAIT_FOR_CLUSTER_START:-1000}"
fi

# Build xcalar-gui so that expServer will run
export XLRGUIDIR=$PWD/xcalar-gui
(cd $XLRGUIDIR && make dev)

# Clean up
sudo pkill -9 usrnode || true
sudo pkill -9 childnode || true
sudo pkill -9 xcmonitor || true
sudo pkill -9 xcmgmtd || true
xclean

# build
cmBuild clean
cmBuild config prod
cmBuild qa

# Copy in the sqlite db file locally from netstore
# This is because the nfs file locking is flaky(seen that taking in minutes)
cp $PERFTEST_DB $XLRDIR/
python "$XLRDIR/src/bin/tests/perfTest/runPerf.py" -p "" -t "$XLRDIR/src/bin/tests/perfTest/perfTests" -r "$XLRDIR/perf.db" -s "`git rev-parse HEAD`"
ret="$?"

[ "$ret" = "0" ] || exit 1

python "$XLRDIR/src/bin/tests/perfTest/perfResults.py" -r "$XLRDIR/perf.db"
ret="$?"

[ "$ret" = "0" ] || exit 2

# Copy out the sqlite db file to netstore on success
cp $XLRDIR/perf.db $PERFTEST_DB

exit 0
