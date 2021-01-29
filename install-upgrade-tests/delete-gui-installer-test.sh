#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] [-i <input file>|-n <id number>] -f <test JSON file>"
    say "-i - read TEST_ID from from input file"
    say "-n - read TEST_ID from command line"
    say "-f - the name of the JSON test file"
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

                . $INPUT_FILE
                ;;
            -n)
                TEST_ID="$1"
                shift
                ;;
            -f)
                TEST_FILE="$1"
                shift
                ;;
            *)
                say "Unknown command $cmd"
                usage
                exit 1
        esac
    done

    if [ -z "$TEST_ID" ]; then
        say "TEST_ID is not set, either by command line or file."
        exit 1
    fi

    if [ ! -e $TEST_FILE ]; then
        say "Test config file $TEST_FILE does not exist"
        exit 1
    fi
}

parse_test_file() {
    task "Parsing test config file"
    t_start="$(date +%s)"
    TEST_NAME=$(jq -r ".TestName" $TEST_FILE)
    TEST_NAME="${CLOUD_PROVIDER}"installtest-"${TEST_NAME}-$TEST_ID"
    TESTHOST_OSVER=$(jq -r ".TestHostConfig.OSVersion" $TEST_FILE)
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

delete_hosts() {
    task "Deleting ${CLOUD_PROVIDER} cluster $TEST_NAME"
    t_start="$(date +%s)"

    if [ -z "${EXISTING_CLUSTER}" ]; then
        cloud_cluster_delete $TEST_NAME 0<&- >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
    else
        echo -e "### Not deleting ${CLOUD_PROVIDER} cluster ${TEST_NAME}. Please delete your cluster without fail! ###"
    fi

    CLUSTER_PID=$!
    wait $CLUSTER_PID
    rc=$?
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} ${TEST_NAME} cluster successfully deleted"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} ${TEST_NAME} cluster delete failed"
        cat $TMPDIR/std* >&2
    fi

    task "Deleting ${CLOUD_PROVIDER} cluster ${TEST_NAME}-install"
    t_start="$(date +%s)"

    if [ -z "${EXISTING_CLUSTER}" ]; then
        cloud_cluster_delete "${TEST_NAME}-install" >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
    else
        echo -e "### Not deleting ${CLOUD_PROVIDER} cluster ${TEST_NAME}-install. Please delete your cluster without fail! ###"
    fi

    INSTALLER_PID=$!
    wait
    rc=$?
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} ${TEST_NAME}-install cluster successfully deleted"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} ${TEST_NAME}-install cluster delete failed"
        cat $TMPDIR/std* >&2
    fi

    if [ "$TESTHOST_OSVER" != "null" ]; then
        task "Deleting ${CLOUD_PROVIDER} cluster ${TEST_NAME}-test"
        t_start="$(date +%s)"

        if [ -z "${EXISTING_CLUSTER}" ]; then
            cloud_cluster_delete "${TEST_NAME}-test" >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
        else
            echo -e "### Not deleting ${CLOUD_PROVIDER} cluster ${TEST_NAME}-test. Please delete your cluster without fail! ###"
        fi

        INSTALLER_PID=$!
        wait
        rc=$?
        t_end="$(date +%s)"
        dt=$(( $t_end - $t_start ))

        if [ $rc -eq 0 ]; then
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} ${TEST_NAME}-test successfully deleted"
        else
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} ${TEST_NAME}-test delete failed"
            cat $TMPDIR/std* >&2
            return $rc
        fi
    fi
}

parse_args "$@"

parse_test_file

delete_hosts
