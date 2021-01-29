#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] -i <input file>"
    say "-c - create/initialize the needed NFS mount"
    say "-r - remove the necessary nfs mount"
    say "-i - input file describing the cluster"
    say "-t - name of test from the JSON file to execute"
    say "-f - JSON file describing the cluster and the tests to run"
    say "-h|--help - this help message"
}


parse_args() {

    if [ -z "$1" ]; then
        usage
        exit 1
    fi

    while test $# -gt 0; do
        cmd="$1"
        shift
        case $cmd in
            --help|-h)
                usage
                exit 1
                ;;
            -c)
                NFS_CMD="create"
                ;;
            -r)
                NFS_CMD="remove"
                ;;
            -t)
                TEST_CASE="$1"
                shift
                ;;
            -i)
                INPUT_FILE="$1"
                shift

                if [ ! -e "$INPUT_FILE" ]; then
                    say "Input config file $INPUT_FILE does not exist"
                    exit 1
                fi
                . $INPUT_FILE
                ;;
            -f)
                TEST_FILE="$1"
                shift

                if [ ! -e "$TEST_FILE" ]; then
                    say "Test config file $TEST_FILE does not exist"
                    exit 1
                fi
                ;;
            *)
                say "Unknown command $cmd"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$TEST_FILE" ]; then
        die 1 "[0] [FAILURE] No test file specified"
    fi

    if [ -z "$INPUT_FILE" ]; then
        say "No input file specified"
        exit 1
    fi

    if [ -z "$NFS_CMD" ]; then
        say "Either -c or -r must be specified"
        exit 1
    fi
}

parse_test_file() {
    task "Parsing test config file"

    t_start="$(date +%s)"
    TEST_NAME=$(jq -r .TestName $TEST_FILE)
    NFS_TYPE=$(jq -r .Build.NfsType $TEST_FILE)
    NFS_SERVER_EXT=$(jq -r .Build.NfsServerExt $TEST_FILE)
    NFS_MOUNT=$(jq -r .Build.NfsMount $TEST_FILE)
    if [ -n "$TEST_CASE" ]; then
        CASE_NFS_TYPE=$(jq -r .BuildCase.$TEST_CASE.NfsType $TEST_FILE)
        if [ "$CASE_NFS_TYPE" != "null" ]; then
            NFS_TYPE="$CASE_LDAP_TYPE"
        fi

        CASE_NFS_SERVER_EXT=$(jq -r .BuildCase.$TEST_CASE.NfsServerExt $TEST_FILE)
        if [ "$CASE_NFS_SERVER" != "null" ]; then
            NFS_SERVER_EXT="$CASE_NFS_SERVER_EXT"
        fi

        CASE_NFS_MOUNT=$(jq -r .BuildCase.$TEST_CASE.NfsMount $TEST_FILE)
        if [ "$CASE_NFS_MOUNT" != "null" ]; then
            NFS_MOUNT="$CASE_NFS_MOUNT"
        fi
    fi
}

parse_args "$@"

parse_test_file

task "Testing cluster"

is_int_ext "NFS_TYPE" "$NFS_TYPE"

case "$NFS_TYPE" in
    int|INT)
        exit 0
        ;;
esac

case $NFS_MOUNT in
    srv/share/jenkins*)
        ;;
    *)
        die 1 "[0] [FAILURE] mount point $NFS_MOUNT is not correct"
        ;;
esac

FULL_MOUNT_POINT="/$NFS_MOUNT/$TEST_NAME-$TEST_ID"

case "$NFS_CMD" in
    create)
        task "Adding NFS export $NFS_MOUNT on server $NFS_SERVER"
        case "${CLOUD_PROVIDER}" in
            aws)
                ssh_cmd "$NFS_SERVER_EXT" "sudo mkdir -p $FULL_MOUNT_POINT" && \
                    ssh_cmd "$NFS_SERVER_EXT" "sudo chmod 1777 $FULL_MOUNT_POINT" || \
                    die 1 "[0] [FAILURE] Unable to create NFS mount"
                ;;
            gce)
                ssh_cmd "$NFS_SERVER_EXT" "sudo mkdir -p ${FULL_MOUNT_POINT}/sub" && \
                    ssh_cmd "$NFS_SERVER_EXT" "sudo chmod 1777 $FULL_MOUNT_POINT" && \
                    ssh_cmd "$NFS_SERVER_EXT" "sudo chown -R nobody:nogroup $FULL_MOUNT_POINT" || \
                    die 1 "[0] [FAILURE] Unable to create NFS mount"
                ;;
        esac
        ;;
    remove)
        task "Removing NFS export $NFS_MOUNT on server $NFS_SERVER"
        ssh_cmd "$NFS_SERVER_EXT" "sudo rm -rf $FULL_MOUNT_POINT" || \
            die 1 "[0] [FAILURE] Unable to remove NFS mount"
        ;;
esac

echo "[0] [SUCCESS] NFS operation successful"

exit 0
