#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help]  [-t <test name>] -i <input file> -d -f <test JSON file>"
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

hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
remote_path="PATH=${INSTALL_DIR}/opt/xcalar/bin:/sbin:/usr/sbin:\$PATH"

task "Starting Xcalar service"
pssh_cmd "${remote_path} ${INSTALL_DIR}/opt/xcalar/bin/xcalarctl start" || die 1 "[0] [FAILURE] Unable to start Xcalar up"
echo "[0] [SUCCESS] Xcalar started"
