#!/bin/bash

set -o pipefail

export XLRDIR=`pwd`
export PATH="$XLRDIR/bin:$HOME/google-cloud-sdk/bin:$PATH"
export GUITSTDIR="$XLRDIR/pkg/gui-installer/integration-tests"
export TMPDIR="/tmp/$(id -un)/$JOB_NAME"
export JOB_TMPDIR="${TMPDIR:-/tmp/$(id -un)}/gui-tst"

rm -rf xcalar-infra
rm -f jenkins-test-key*
git clean -fxd
git reset --hard HEAD
git clone 'ssh://gerrit.int.xcalar.com:29418/xcalar/xcalar-infra.git' xcalar-infra

cd xcalar-infra
git checkout $XCALAR_INFRA_BRANCH
cd ..
export XLRINFRADIR="$XLRDIR/xcalar-infra"

PRIV_KEY_FILE="jenkins-test-${RANDOM}"
PUB_KEY_FILE="${PRIV_KEY_FILE}.pub"

ssh-keygen -t rsa -N "" -f $PRIV_KEY_FILE

export BUILD_PUBLIC_KEY=$(readlink -f ./$PUB_KEY_FILE)
export BUILD_LICENSE_FILE=$(readlink -f ./src/data/XcalarLic.key)

export BUILD_NFS_SERVER="10.128.0.6"
export BUILD_NFS_SERVER_EXT="146.148.59.48"
export BUILD_NFS_MOUNT_ROOT="srv/share/jenkins"
export BUILD_LDAP_SERVER="10.128.0.5"

INSTALLER_FILE=$BUILD_DIRECTORY/$BUILD_FILE
INSTALLER_FILE=$(readlink -f $INSTALLER_FILE)

export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE)
export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)

XCE_GIT_SHA=`echo "$BUILD_INSTALLER_FILE" | cut -d. -f 5`
echo "XCE_GIT_SHA: $XCE_GIT_SHA"

$GUITSTDIR/gen-build-template.sh > $XLRDIR/cluster_build.json 2>&1 || exit 1

NEW_INSTALLER_FILE=${JOB_TMPDIR}/${BUILD_INSTALLER_FILE}

INSTALLER_FILE=$(readlink -f $PRE_UPGRADE_FILE)
export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE)
export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)
export BUILD_PROTOCOL="1.1.0"

$GUITSTDIR/gen-build-template.sh > $XLRDIR/cluster_preupgrade.json

OLD_INSTALLER_FILE=${JOB_TMPDIR}/${BUILD_INSTALLER_FILE}

STAGE_1_RUNNING=1
STAGE_1_COMPLETE=1
STAGE_2_RUNNING=1
STAGE_2_COMPLETE=1
STAGE_3_RUNNING=1
STAGE_3_COMPLETE=1
STAGE_4_RUNNING=1
STAGE_4_COMPLETE=1
STAGE_5_RUNNING=1
STAGE_5_COMPLETE=1

cat $XLRDIR/cluster_build.json

echo "## Stage 1"
echo "## run-gui-installer-test - create cluster"
echo "## nfs-manage -- set up any NFS storage (if necessary)"
echo "## curl installer -- install $NEW_INSTALLER_FILE"
echo "## add-ldap-users -- add extra ldap users"
echo "## test-running -- verify all processes running"

$GUITSTDIR/run-gui-installer-test.sh -f $XLRDIR/cluster_build.json -o $XLRDIR/cluster.data && \
    cat cluster.data && echo && sleep 20 && \
    $GUITSTDIR/nfs-manage.sh -c -f cluster_build.json -i cluster.data && \
    $GUITSTDIR/curl-installer.sh -f cluster_build.json -i cluster.data && sleep 10 && \
    $GUITSTDIR/add-ldap-users.sh -f cluster_build.json -i cluster.data && \
    $GUITSTDIR/test-running.sh -f cluster_build.json -i cluster.data
STAGE_1_RUNNING=$?

echo "## STAGE_1_RUNNING: $STAGE_1_RUNNING"
echo "##"
echo
echo "## test-ui - run ui test"
echo "## test-login - try a login"
echo "## shutdown-delete - shutdown and delete shared area"
echo "## uinstaller - uninstall $NEW_INSTALLER_FILE"

#if [ 1 -eq 0 ]; then
if [ $STAGE_1_RUNNING -eq 0 ]; then
    $GUITSTDIR/test-ui.sh -i cluster.data && sleep 10 && \
        $GUITSTDIR/test-login.sh -i cluster.data -u "$TEST_USER_NAME" -p "$TEST_PASSWORD" && \
        $GUITSTDIR/shutdown-delete.sh -t -d -f cluster_build.json -i cluster.data && \
        $GUITSTDIR/uninstaller.sh -f cluster_build.json -i cluster.data && sleep 10 && \
        STAGE_1_COMPLETE=$?
fi

echo "## STAGE_1_COMPLETE: $STAGE_1_COMPLETE"
echo "##"
echo
echo "## Stage 2"
echo "## restart-installer - load $OLD_INSTALLER_FILE"
echo "## curl-installer - install $OLD_INSTALLER_FILE"
echo

#if [ 1 -eq 0 ]; then
if [ $STAGE_1_COMPLETE -eq 0 ]; then
    cat $XLRDIR/cluster_preupgrade.json

    $GUITSTDIR/restart-installer.sh -f $XLRDIR/cluster_preupgrade.json -i cluster.data && \
        $GUITSTDIR/curl-installer.sh -f $XLRDIR/cluster_preupgrade.json -i cluster.data
    STAGE_2_RUNNING=$?

    $GUITSTDIR/test-running.sh -f cluster_build.json -i cluster.data
fi

echo "## STAGE_2_RUNNING: $STAGE_2_RUNNING"
echo "##"
echo
echo "## test-ui - run a ui test on the old instance"
echo "## shutdown-delete - just shutdown the old instance"
echo "## backup-recover - backup the shared storage"

#if [ 1 -eq 0 ]; then
if [ $STAGE_2_RUNNING -eq 0 ]; then
    $GUITSTDIR/test-ui.sh -i cluster.data && sleep 30 && \
        $GUITSTDIR/shutdown-delete.sh -t -f cluster_preupgrade.json -i cluster.data && \
        $GUITSTDIR/backup-recover.sh -f cluster_preupgrade.json -i cluster.data -b
    STAGE_2_COMPLETE=$?
fi

echo "## STAGE_2_COMPLETE: $STAGE_2_COMPLETE"
echo "##"
echo
echo "## Stage 3"
echo "## restart-installer - load $NEW_INSTALLER_FILE"
echo "## curl-installer - install $NEW_INSTALLER_FILE"
echo "## add-ldap-users -- add extra ldap users"
echo "## test-running -- verify all processes running"

#if [ 1 -eq 0 ]; then
if [ $STAGE_2_COMPLETE -eq 0 ]; then
    $GUITSTDIR/restart-installer.sh -f $XLRDIR/cluster_build.json -i cluster.data && \
        $GUITSTDIR/curl-installer.sh -f $XLRDIR/cluster_build.json -i cluster.data && sleep 10 && \
        $GUITSTDIR/add-ldap-users.sh -f cluster_build.json -i cluster.data && \
        $GUITSTDIR/test-running.sh -f cluster_build.json -i cluster.data
    STAGE_3_RUNNING=$?
fi

echo "## STAGE_3_RUNNING: $STAGE_3_RUNNING"
echo "##"
echo
echo "## Run UI Verification test"
echo "## test-login - try a login"
echo "## shutdown-delete - shutdown (no delete)"
echo "## backup-recover - recover the shared storage"

if [ $STAGE_3_RUNNING -eq 0 ]; then
    # UI Verification Test here && \
    $GUITSTDIR/test-login.sh -i cluster.data -u "$TEST_USER_NAME" -p "$TEST_PASSWORD" && \
        $GUITSTDIR/shutdown-delete.sh -f cluster_build.json -i cluster.data && sleep 10 && \
        $GUITSTDIR/backup-recover.sh -f cluster_preupgrade.json -i cluster.data -r
    STAGE_3_COMPLETE=$?
fi


echo "## STAGE_3_COMPLETE: $STAGE_3_COMPLETE"
echo "##"
echo
echo "## Stage 4"
echo "## startup - startup the instance with old files"
echo "## test-running -- verify all processes running with old files"
echo "## Run UI Verification test on the upgraded instance with old files"
echo "## test-ui - run a UI test on the upgraded instance with old files"

if [ $STAGE_3_COMPLETE -eq 0 ]; then
    $GUITSTDIR/startup.sh -f cluster_build.json -i cluster.data  && sleep 20 && \
        $GUITSTDIR/test-running.sh -f cluster_build.json -i cluster.data # && sleep 10 && \
    # UI Verification Test here &&
    # UI Workspace Modify here && \
    #$GUITSTDIR/test-ui.sh -i cluster.data
    STAGE_4_RUNNING=$?
fi

echo "## STAGE_4_RUNNING: $STAGE_4_RUNNING"
echo "##"
echo
echo "## shutdown-delete - shutdown with delete of shared storage"
echo "## startup - startup with no files"
echo "## test-ui - start some cluster activity"
echo "## kill-usrnode - crash the cluster"
echo "## shutdown-delete - shutdown the rest of the cluster"
echo "## startup - restart the cluster"
echo "## test-running - verify all processes have restarted"

if [ $STAGE_4_RUNNING -eq 0 ]; then
    CRASH_WAIT=$(( 15 + ${RANDOM}%10 ))

    $GUITSTDIR/shutdown-delete.sh -d -f cluster_build.json -i cluster.data && sleep 10 && \
        $GUITSTDIR/startup.sh -f cluster_build.json -i cluster.data && sleep 10 && \
        $GUITSTDIR/test-ui.sh -i cluster.data -s && sleep $CRASH_WAIT && \
        $GUITSTDIR/kill-usrnode.sh -i cluster.data && sleep 10 && \
        $GUITSTDIR/shutdown-delete.sh -f cluster_build.json -i cluster.data && sleep 30 && \
        $GUITSTDIR/startup.sh -f cluster_build.json -i cluster.data && sleep 10 && \
        $GUITSTDIR/test-running.sh -f cluster_build.json -i cluster.data
    STAGE_4_COMPLETE=$?
fi
echo "## STAGE_4_COMPLETE: $STAGE_4_COMPLETE"
echo "##"


rm -f ${NEW_INSTALLER_FILE} ${OLD_INSTALLER_FILE} &&
echo "${NEW_INSTALLER_FILE} and ${OLD_INSTALLER_FILE} deleted" && echo

$GUITSTDIR/delete-gui-installer-test.sh -f $XLRDIR/cluster_build.json -i $XLRDIR/cluster.data
$GUITSTDIR/nfs-manage.sh -r -f cluster_build.json -i cluster.data

GRAPHITE_OUTPUT="prod.instupgradetests.${BUILD_TEST_NAME}.${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}:${STAGE_4_COMPLETE}|g"

echo  "$GRAPHITE_OUTPUT" | nc -4 -w 5 -u $GRAPHITE 8125

echo "Value sent to graphite: $GRAPHITE_OUTPUT"

source cluster.data

if [ "$STAGE_4_COMPLETE" = "0" ]; then
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.status:0|g" | nc -4 -w 5 -u $GRAPHITE 8125
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numPass:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
else
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.status:1|g" | nc -4 -w 5 -u $GRAPHITE 8125
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numRun:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numFail:1|c" | nc -4 -w 5 -u $GRAPHITE 8125
fi

echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO"

exit $STAGE_4_COMPLETE
