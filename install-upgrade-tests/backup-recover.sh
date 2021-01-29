#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

OP="none"

usage() {
    say "usage: $0 [-h|--help] -i <input file>"
    say "-b - perform a shared storage backup"
    say "-r - perform a shared storage recover"
    say "-i - input file describing the cluster"
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
            -b)
                OP="backup"
                ;;
            -r)
                OP="recover"
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
        say "No test file specified"
        exit 1
    fi

    if [ -z "$INPUT_FILE" ]; then
        say "No input file specified"
        exit 1
    fi
}

parse_test_file() {
    task "Parsing test config file"
    t_start="$(date +%s)"

    TEST_NAME=$(jq -r ".TestName" $TEST_FILE)
    INSTALL_DIR=$(jq -r ".Build.InstallDir" $TEST_FILE)

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

parse_args "$@"

parse_test_file

task "Finding XcalarRoot"
NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
find_xce_path "$NODE_ZERO" "$INSTALL_DIR" || die 1 "Unable to find XCE Root Path"

echo "XCE_ROOT_PATH is $XCE_ROOT_PATH"

task "Making sure that rsync is installed"
ssh_cmd "$NODE_ZERO" "sudo yum install -y rsync || true"

case "$OP" in
    backup)
        task "Copying XcalarRoot to backup"
        ssh_cmd "$NODE_ZERO" "sudo rsync -av $XCE_ROOT_PATH/ /backup/back"
        rc=$?
        ;;
    recover)
        task "Copying XcalarRoot from backup"
        ssh_cmd "$NODE_ZERO" "test -d /backup/back && sudo rsync -av /backup/back/ $XCE_ROOT_PATH"
        # we eat rc=23 because of NFS issues
        rc=$?
        [ $rc -eq 23 ] && rc=0
        ;;
esac

exit $rc
