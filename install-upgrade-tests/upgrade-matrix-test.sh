#!/bin/bash

set -o pipefail

#
# snip
#
export XLRDIR=${XLRDIR:-$PWD}
#export PATH="$XLRDIR/bin:$HOME/google-cloud-sdk/bin:$PATH"
export GUITSTDIR="$XLRDIR/pkg/gui-installer/integration-tests"
#export TMPDIR="/tmp/$(id -un)/$JOB_NAME"
#export JOB_TMPDIR="${TMPDIR:-/tmp/$(id -un)}/gui-tst"
export TEST_DATA_PATH=${TEST_DATA_PATH:-/netstore/datasets/upgrade-tests}

#rm -rf xcalar-infra
#rm -f jenkins-test-key*
#git clean -fxd
#git reset --hard HEAD
#git clone 'ssh://gerrit.int.xcalar.com:29418/xcalar/xcalar-infra.git' xcalar-infra

#cd xcalar-infra
#git checkout $XCALAR_INFRA_BRANCH
#cd ..
#export XLRINFRADIR="$XLRDIR/xcalar-infra"

PRIV_KEY_FILE="jenkins-test-${RANDOM}"
PUB_KEY_FILE="${PRIV_KEY_FILE}.pub"

ssh-keygen -t rsa -N "" -f $PRIV_KEY_FILE

export BUILD_PUBLIC_KEY=$(readlink -f ./$PUB_KEY_FILE)
export BUILD_LICENSE_FILE=$(readlink -f $XLRDIR/src/data/XcalarLic.key)

export BUILD_NFS_SERVER=${BUILD_NFS_SERVER:-"10.128.0.6"}
export BUILD_NFS_SERVER_EXT=${BUILD_NFS_SERVER_EXT:-"146.148.59.48"}
export BUILD_NFS_MOUNT_ROOT=${BUILD_NFS_MOUNT_ROOT:-"srv/share/jenkins"}
export BUILD_LDAP_SERVER=${BUILD_LDAP_SERVER:-"10.128.0.5"}

#
# /snip
#

test_idl_change () {
    local from_ver="$(echo $1 | cut -d- -f2)"
    local to_ver="$(echo $2 | cut -d- -f2)"

    FROM_A=$(echo "$from_ver" | cut -d. -f1)
    FROM_B=$(echo "$from_ver" | cut -d. -f2)

    TO_A=$(echo "$to_ver" | cut -d. -f1)
    TO_B=$(echo "$to_ver" | cut -d. -f2)

    if [ "$FROM_A" -le 1 ] && [ "$FROM_B" -lt 2 ] && \
        [ "$TO_A" -ge 1 ] && [ "$TO_B" -ge 2 ]; then
        return 0
    fi

    return 1
}

run_user_intervention () {
    if test_idl_change "$1" "$2"; then
        # no op (for now)
        :
    fi

    if [ -n "$INTER_RUN_SCRIPT" ] && [ -f "$INTER_RUN_SCRIPT" ]; then
        $INTER_RUN_SCRIPT "$ACTIVE_JSON_FILE" "$BASE_DATA_FILE" "$1" "$2"
    fi
}

get_installer_protocol () {
    case "$1" in
        1.2.0|1.2.1)
            export BUILD_PROTOCOL=1.2.0
            ;;
        *)
            export BUILD_PROTOCOL=1.2.1
            ;;
    esac
}

get_data_version () {
    local ver="$(echo $1 | cut -d- -f2)"

    case "$ver" in
        *)
            export TEST_DATA_SET="xcalar-1.2-dataset.tgz"
            ;;
    esac
}

get_test_running_value () {
    case "$ver" in
        1.2.0|1.2.1)
            TEST_RUNNING_RC=64
            ;;
        *)
            TEST_RUNNING_RC=0
            ;;
    esac
}

RELEASE_DIR=${RELEASE_DIR:-"/netstore/builds/ReleaseCandidates"}

ALL_XLR_VERSIONS="$(find $RELEASE_DIR -maxdepth 1 -type d -regex '.*/xcalar-.*-RC[0-9]+$' -exec basename {} \; | grep -E -v '1.0.3|1.1.[0-9]+' | sort -u | cut -d- -f2 | sort -u)"

TEST_XLR_VERSIONS=( $(for ver in $ALL_XLR_VERSIONS; do find $RELEASE_DIR -maxdepth 1 -type d -regex ".*/xcalar-${ver}-RC[0-9]+$" -exec basename {} \; | sort -u | tail -1; done) )

TEST_XLR_MAX=$(( ${#TEST_XLR_VERSIONS[@]} - 1 ))

TEST_RC=0
CLUSTER_BUILT=1

for ii in `seq 0 $(( $TEST_XLR_MAX - 1 ))`; do
    BASE_VERSION="$(echo "${TEST_XLR_VERSIONS[$ii]}" | cut -d- -f2)"
    BUILD_DIR="$(ls -d ${RELEASE_DIR}/${TEST_XLR_VERSIONS[$ii]}/* | tail -1)"
    INSTALLER_FILE="$(find ${BUILD_DIR}/prod -name "xcalar-gui-installer.${BASE_VERSION}.*.sh")"
    INSTALLER_FILE="$(readlink -f $INSTALLER_FILE)"

    export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE)
    export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)
    export BASE_JSON_FILE="./cluster_base.json"
    export BASE_DATA_FILE="./cluster.data"
    export ACTIVE_JSON_FILE="$BASE_JSON_FILE"

    get_installer_protocol "$BASE_VERSION"
    $GUITSTDIR/gen-build-template.sh >"$BASE_JSON_FILE" 2>&1 || exit 1

    cat "$BASE_JSON_FILE"

    if [ $CLUSTER_BUILT -eq 1 ]; then
        $GUITSTDIR/run-gui-installer-test.sh -f "$BASE_JSON_FILE" -o "$BASE_DATA_FILE" && \
            cat "$BASE_DATA_FILE" && echo && sleep 20 && \
            $GUITSTDIR/nfs-manage.sh -c -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE" && \
            $GUITSTDIR/setup-netstore.sh -i "$BASE_DATA_FILE"
        CLUSTER_BUILT=$?

        if [ $CLUSTER_BUILT -ne 0 ]; then
            break
        fi

        BASE_INSTALLER_RUNNING=0
    fi

    BASE_CLUSTER_RUNNING=1
    UPGRADE_INSTALLER_RUNNING=1
    UPGRADE_CLUSTER_RUNNING=1

    for jj in `seq $(( $ii + 1 )) $TEST_XLR_MAX`; do
        get_test_running_value $BASE_VERSION
        if [ $BASE_INSTALLER_RUNNING -eq 0 ]; then
            $GUITSTDIR/curl-installer.sh -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE" && sleep 10 && \
                $GUITSTDIR/add-ldap-users.sh -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE" && \
                $GUITSTDIR/test-running.sh -r $TEST_RUNNING_RC -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE"
            BASE_CLUSTER_RUNNING=$?
        fi

        UPGRADE_VERSION="$(echo "${TEST_XLR_VERSIONS[$jj]}" | cut -d- -f2)"
        BUILD_DIR="$(ls -d ${RELEASE_DIR}/${TEST_XLR_VERSIONS[$jj]}/* | tail -1)"
        INSTALLER_FILE="$(find ${BUILD_DIR}/prod -name "xcalar-gui-installer.${UPGRADE_VERSION}.*.sh")"
        INSTALLER_FILE="$(readlink -f $INSTALLER_FILE)"

        export BUILD_INSTALLER_FILE=$(basename $INSTALLER_FILE)
        export BUILD_INSTALLER_DIR=$(dirname $INSTALLER_FILE)
        export UPDATE_JSON_FILE="./cluster_upgrade.json"

        get_installer_protocol "$UPGRADE_VERSION"
        $GUITSTDIR/gen-build-template.sh > "$UPDATE_JSON_FILE" 2>&1 || exit 1

        cat "$UPDATE_JSON_FILE"

        if [ $BASE_CLUSTER_RUNNING -eq 0 ]; then
            $GUITSTDIR/shutdown-delete.sh -d -t -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE" && \
                 $GUITSTDIR/restart-installer.sh -f "$UPDATE_JSON_FILE" -i "$BASE_DATA_FILE"            
            UPGRADE_INSTALLER_RUNNING=$?
            BASE_INSTALLER_RUNNING=1
        fi

        if [ $UPGRADE_INSTALLER_RUNNING -eq 0 ]; then
            get_data_version "${TEST_XLR_VERSIONS[$ii]}"
            get_test_running_value $UPGRADE_VERSION
            echo "#"
            echo "# copying test data set to cluster"
            echo "#"
            $GUITSTDIR/install-upgrade-dataset.sh -f "${TEST_DATA_PATH}/${TEST_DATA_SET}" -i "$BASE_DATA_FILE"

            echo -n "# Upgrade ${TEST_XLR_VERSIONS[$ii]} to ${TEST_XLR_VERSIONS[$jj]}"
            run_user_intervention ${TEST_XLR_VERSIONS[$ii]} ${TEST_XLR_VERSIONS[$jj]}
            export ACTIVE_JSON_FILE="$UPDATE_JSON_FILE"

            $GUITSTDIR/curl-installer.sh -f "$UPDATE_JSON_FILE" -i "$BASE_DATA_FILE" && sleep 10 && \
                $GUITSTDIR/add-ldap-users.sh -f "$UPDATE_JSON_FILE" -i "$BASE_DATA_FILE" && \
                $GUITSTDIR/test-running.sh -r $TEST_RUNNING_RC  $-f "$UPDATE_JSON_FILE" -i "$BASE_DATA_FILE" && \
                $GUITSTDIR/activate-upgrade-dataset.sh -i "$BASE_DATA_FILE"
            UPGRADE_CLUSTER_RUNNING=$?
            TEST_RC=$(( $TEST_RC + $UPGRADE_CLUSTER_RUNNING ))
        fi

        if [ $UPGRADE_CLUSTER_RUNNING -eq 0 ]; then
            $GUITSTDIR/shutdown-delete.sh -d -t -f "$UPDATE_JSON_FILE" -i "$BASE_DATA_FILE" && \
                 $GUITSTDIR/restart-installer.sh -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE"            
            BASE_INSTALLER_RUNNING=$?
            export ACTIVE_JSON_FILE="$BASE_JSON_FILE"
        fi

        BASE_CLUSTER_RUNNING=1
        UPGRADE_INSTALLER_RUNNING=1
        UPGRADE_CLUSTER_RUNNING=1
    done

    echo ""
done

$GUITSTDIR/delete-gui-installer-test.sh -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE"
$GUITSTDIR/nfs-manage.sh -r -f "$BASE_JSON_FILE" -i "$BASE_DATA_FILE"

if [ "$TEST_RC" != "0" ]; then
    exit 1
fi

exit 0
