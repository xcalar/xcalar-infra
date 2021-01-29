#!/bin/bash

# Inputs (with sample values):
# GIT_BRANCH: user/thaining-gce-test
# GIT_REPOSITORY: git@git:/gitrepos/xcalar-prototype.git
# BUILD_DIRECTORY: /netstore/qa/Downloads/byJob/BuildTrunk
# BUILD_FILE: xcalar-latest-gui-installer-prod.sh
# BUILD_TEST_NAME: centos7build
# BUILD_CLUSTER_SIZE: 2
# BUILD_CLUSTER_OS: CENTOS7
# XCALAR_INFRA_BRANCH: master
# GCE
# BUILD_CLUSTER_IMAGE: centos-7-v20170227
# AWS
# BUILD_CLUSTER_IMAGE: ami-4185e621
# BUILD_CLUSTER_PROJECT: centos-cloud
# PRE_UPGRADE_FILE: /netstore/builds/ReleaseCandidates/xcalar-1.1.2-RC4/20170503-ec418db7/prod/xcalar-gui-installer.1.1.2.ec418db7.sh
# TEST_USER_NAME: jenkins@gmail.com
# TEST_PASSWORD: welcome1
# BUILD_NFS_TYPE: INT
# BUILD_LDAP_TYPE: INT
# IGNORE_UI_TEST: 1
# AWS
# CLOUDFORMATION_JSON: file:///netstore/infra/aws/cfn/XCE-CloudFormationInstallerTest.json

set -o pipefail

export PATH="/opt/xcalar/bin:$PATH"
export WRKDIR="${WRKDIR:-$WORKSPACE}"
export XLRDIR="${WRKDIR}/xcalar"
export XLRINFRADIR="${WRKDIR}/xcalar-infra"
export PATH="$XLRDIR/bin:$HOME/google-cloud-sdk/bin:$PATH"
export GUITSTDIR="$XLRINFRADIR/install-upgrade-tests"
export JOB_NAME="${JOB_NAME:-Install-Test}"
export TMPDIR="/tmp/$(id -un)/$JOB_NAME"
export JOB_TMPDIR="${TMPDIR:-/tmp/$(id -un)}/gui-tst"
LICENSE_FILE="${LICENSE_FILE:-$XLRDIR/src/data/XcalarLic.key}"

rm -f ${WRKDIR}/jenkins-test-* ${WRKDIR}/cluster_*.json ${WRKDIR}/cluster.data

. $XLRDIR/bin/osid > /dev/null

VERSTRING="$(_osid --full)"

case ${OSID_NAME} in
    el|rhel)
        distro="el${OSID_VERSION}"
        ;;
    *)
        distro="$VERSTRING"
        ;;
esac

case "$distro" in
    el*)
        sudo yum -y install sshpass || true
        sudo yum -y install awscli || true
        ;;
    ub14)
        sudo apt-get install -y sshpass
        sudo apt-get install -y awscli
        ;;
    *)
        echo >&2 "Error: unknown OS version ${distro}"
        ;;
esac

case "$CLOUD_PROVIDER" in
    aws)
        export AWS_SSH_OPT="-o IdentityFile=$AWS_PEM"
        ;;
    gce)
        if [ -z "GCE_SLAVE_SETUP" ]; then
            /netstore/users/jenkins/slave/setup.sh

            if test -z "$SSH_AUTH_SOCK"; then
                eval `ssh-agent`
            fi

            if test -n "$SSH_AUTH_SOCK" && test -w "$SSH_AUTH_SOCK"; then
                if ! ssh-add -l | grep -q 'google_compute_engine'; then
                    test -f ~/.ssh/google_compute_engine && ssh-add ~/.ssh/google_compute_engine
                fi
            fi
        fi
        ;;
esac

PRIV_KEY_FILE="${WRKDIR}/jenkins-test-${RANDOM}"
PUB_KEY_FILE="${PRIV_KEY_FILE}.pub"

ssh-keygen -t rsa -N "" -f $PRIV_KEY_FILE

export BUILD_PUBLIC_KEY=$(readlink -f $PUB_KEY_FILE)
export BUILD_LICENSE_FILE=$(readlink -f $LICENSE_FILE)

INSTALLER_FILE=$BUILD_DIRECTORY/$BUILD_FILE
INSTALLER_FILE=$(readlink -f $INSTALLER_FILE)

export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE)
export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)

XCE_JENKINS_BUILD_DIR="$(dirname "$BUILD_INSTALLER_DIR")"
XCE_GIT_SHA="$(cat ${XCE_JENKINS_BUILD_DIR}/BUILD_SHA | head -1 | cut -d '(' -f 2 | cut -d ')' -f 1)"

echo "cloud provider"
echo ${CLOUD_PROVIDER:-aws}

export BUILD_PROTOCOL="${BUILD_PROTOCOL:-1.3.0}"

$GUITSTDIR/gen-build-template.sh > "${WRKDIR}/cluster_build.json" 2>&1 || exit 1

NEW_INSTALLER_FILE=${JOB_TMPDIR}/${BUILD_INSTALLER_FILE}

INSTALLER_FILE=$(readlink -f $PRE_UPGRADE_FILE)
export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE) export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)
export BUILD_PRECONFIG_FILE="${PRE_UPGRADE_PRECONFIG_FILE:-NULL}"
export BUILD_PROTOCOL="${PREUPGRADE_BUILD_PROTOCOL:-$BUILD_PROTOCOL}"

$GUITSTDIR/gen-build-template.sh > "${WRKDIR}/cluster_preupgrade.json" 2>&1 || exit 1

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

echo "#"
echo "# Test Config"
echo "#"
cat "${WRKDIR}/cluster_build.json"

echo "## Stage 1"
echo "## run-gui-installer-test - create cluster"
echo "## nfs-manage -- set up any NFS storage (if necessary)"
echo "## curl installer -- install $NEW_INSTALLER_FILE"
echo "## add-ldap-users -- add extra ldap users"
echo "## test-running -- verify all processes running"

$GUITSTDIR/run-gui-installer-test.sh -f "${WRKDIR}/cluster_build.json" -o "${WRKDIR}/cluster.data" && \
    cat "${WRKDIR}/cluster.data" && echo && sleep 20 && \
    $GUITSTDIR/nfs-manage.sh -c -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
    $GUITSTDIR/curl-installer.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
    $GUITSTDIR/add-ldap-users.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
    $GUITSTDIR/test-running.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"
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
    $GUITSTDIR/test-ui.sh -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/test-login.sh -i "${WRKDIR}/cluster.data" -u "$TEST_USER_NAME" -p "$TEST_PASSWORD" && \
        $GUITSTDIR/shutdown-delete.sh -t -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/curl-uninstaller.sh -d -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/uninstaller.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
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
    cat "${WRKDIR}/cluster_preupgrade.json"

    $GUITSTDIR/restart-installer.sh -f "${WRKDIR}/cluster_preupgrade.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/curl-installer.sh -f "${WRKDIR}/cluster_preupgrade.json" -i "${WRKDIR}/cluster.data"
    STAGE_2_RUNNING=$?

    $GUITSTDIR/test-running.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"
fi

echo "## STAGE_2_RUNNING: $STAGE_2_RUNNING"
echo "##"
echo
echo "## test-ui - run a ui test on the old instance"
echo "## shutdown-delete - just shutdown the old instance"
echo "## backup-recover - backup the shared storage"

#if [ 1 -eq 0 ]; then
if [ $STAGE_2_RUNNING -eq 0 ]; then
    $GUITSTDIR/test-ui.sh -i "${WRKDIR}/cluster.data" && sleep 30 && \
        $GUITSTDIR/shutdown-delete.sh -t -f "${WRKDIR}/cluster_preupgrade.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/backup-recover.sh -f "${WRKDIR}/cluster_preupgrade.json" -i "${WRKDIR}/cluster.data" -b
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
    $GUITSTDIR/restart-installer.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/curl-installer.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
        sleep 10 && \
        $GUITSTDIR/add-ldap-users.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && \
        $GUITSTDIR/test-running.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"
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
    $GUITSTDIR/test-login.sh -i "${WRKDIR}/cluster.data" -u "$TEST_USER_NAME" -p "$TEST_PASSWORD" && \
        $GUITSTDIR/shutdown-delete.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/backup-recover.sh -f "${WRKDIR}/cluster_preupgrade.json" -i "${WRKDIR}/cluster.data" -r
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
    $GUITSTDIR/startup.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"  && sleep 20 && \
        $GUITSTDIR/test-running.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" # && sleep 10 && \
    # UI Verification Test here &&
    # UI Workspace Modify here && \
    #$GUITSTDIR/test-ui.sh -i "${WRKDIR}/cluster.data"
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

    $GUITSTDIR/shutdown-delete.sh -d -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/startup.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/test-ui.sh -i "${WRKDIR}/cluster.data" -s && sleep $CRASH_WAIT && \
        $GUITSTDIR/kill-usrnode.sh -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/shutdown-delete.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 30 && \
        $GUITSTDIR/startup.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data" && sleep 10 && \
        $GUITSTDIR/test-running.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"
    STAGE_4_COMPLETE=$?
fi
echo "## STAGE_4_COMPLETE: $STAGE_4_COMPLETE"
echo "##"


rm -f ${NEW_INSTALLER_FILE} ${OLD_INSTALLER_FILE} && \
    echo "${NEW_INSTALLER_FILE} and ${OLD_INSTALLER_FILE} deleted" && echo

$GUITSTDIR/delete-gui-installer-test.sh -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"
$GUITSTDIR/nfs-manage.sh -r -f "${WRKDIR}/cluster_build.json" -i "${WRKDIR}/cluster.data"

if [ -n "$GRAPHITE" ]; then
    GRAPHITE_OUTPUT="prod.instupgradetests.${BUILD_TEST_NAME}.${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}:${STAGE_4_COMPLETE}|g"

    echo  "$GRAPHITE_OUTPUT" | nc -w 1 -u $GRAPHITE 8125

    echo "Value sent to graphite: $GRAPHITE_OUTPUT"

    source ${WRKDIR}/cluster.data

    if [ "$STAGE_4_COMPLETE" = "0" ]; then
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.status:0|g" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numPass:1|c" | nc -w 1 -u $GRAPHITE 8125
else
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.status:1|g" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numRun:1|c" | nc -w 1 -u $GRAPHITE 8125
        echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO.numFail:1|c" | nc -w 1 -u $GRAPHITE 8125
    fi

    echo "prod.tests.$XCE_GIT_SHA.instupgradetests.${BUILD_TEST_NAME}-${BUILD_NFS_TYPE}${BUILD_LDAP_TYPE}.$NODE_NAME_ZERO"
fi


exit $STAGE_4_COMPLETE
