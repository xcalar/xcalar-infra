#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] -i <input file> -f <test JSON file>"
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
            -x)
                GUI_INSTALL_CACHE=1
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

    #TEST-ID should come from the input file
    TEST_NAME=$(jq -r ".TestName" $TEST_FILE)
    TEST_NAME="${TEST_NAME}-${TEST_ID}"
    INSTALLER_FILE=$(jq -r ".InstallerFile.Name" $TEST_FILE)
    INSTALLER_SRC=$(jq -r ".InstallerFile.Source" $TEST_FILE)
    eval INSTALLER_SRC=$INSTALLER_SRC
    INSTALLER_SRC=$(readlink -f "$INSTALLER_SRC")

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

stop_running_installer_docker() {
    task "Parsing test config file"
    t_start="$(date +%s)"

    ssh_cmd $EXT_INSTALL_IP "sudo docker ps" || \
        die 1 "Unable to contact docker on $EXT_INSTALL_IP"

    INST_CONTAINER_ID=$(grep gui-install $TMPDIR/stdout | awk '{ print $1; }')
    if [ -z $INST_CONTAINER_ID ]; then
        NOT_RUNNING="1"
        return 0
    fi

    echo "Found running docker container $INST_CONTAINER_ID"

    ssh_cmd $EXT_INSTALL_IP "sudo docker stop $INST_CONTAINER_ID"

    while :
    do
        sleep 5
        echo "Checking for installer stop"
        ssh_cmd $EXT_INSTALL_IP "sudo docker ps -q -f id=$INST_CONTAINER_ID"

        if [ -z "$(cat $TMPDIR/stdout)" ]; then
            echo "Installer stopped"
            break
        fi
    done

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Stopping installer"
}

stop_running_installer () {
    task "Parsing test config file"
    t_start="$(date +%s)"

    ssh_cmd $EXT_INSTALL_IP 'PID1=$(pgrep caddy); PID2=$(pgrep node); kill -INT $PID1 $PID2' || die 1 "failed to stop installer"

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Stopping installer"
}


parse_args "$@"

parse_test_file

if [ ! -e ${TMPDIR}/${INSTALLER_FILE} ]; then
    get_installer_file || die $? "Unable to get installer file"
fi

set -o pipefail
stop_running_installer && \
    launch_installer && \
    installer_ready
rc=$?

exit $rc
