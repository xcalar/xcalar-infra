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
    say "-k - force kill the test server process before testing"
    say "-s - start only, do not poll for status"
    say "-i - input file describing the cluster"
    say "-h|--help - this help message"
}

unset SERVER_KILL
unset START_ONLY
TIME_DILATION=5

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
            -s)
                START_ONLY="1"
                ;;
            -k)
                SERVER_KILL="1"
                ;;
            -t)
                TIME_DILATION="$1"
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
            *)
                say "Unknown command $cmd"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$INPUT_FILE" ]; then
        say "No input file specified"
        exit 1
    fi
}

#
# $1 - url
#
run_gui_test_cmd() {
    RETVAL=$(curl -k -sS -m 120 -w "HTTPSTATUS:%{http_code}" -X GET $1 2>&1)
    rc=$?

    if [ $rc -ne 0 ]; then
        server_log_fname="${TMPDIR}/test-ui-server-log.$$.${RANDOM}.log"
        echo "[FAILURE] during command $1 with return code $rc"
        cat $TMPDIR/std* >&2
        echo "Server log: "
        scp_cmd "$EXT_TEST_IP:/tmp/server.log" "$server_log_fname"
        cat "$server_log_fname" >&2
        case $rc in
            52|28)
                SERVER_NOT_RESPONDING=1
                ;;
        esac
    fi

    return $rc
}

test_server_check() {
    _ssh_cmd $EXT_TEST_IP "pgrep -f server.py"
    rc=$?

    return $rc
}

test_server_cleanup() {
    log_name=$1
    rc=0
    _ssh_cmd $EXT_TEST_IP "killall -9 python"
    rc=$(( $rc + $? ))
    _ssh_cmd $EXT_TEST_IP "killall -9 chromium-browser"
    rc=$(( $rc + $? ))
    _ssh_cmd $EXT_TEST_IP "killall -9 chromedriver"
    rc=$(( $rc + $? ))
    _ssh_cmd $EXT_TEST_IP "killall Xvfb"
    rc=$(( $rc + $? ))
    _ssh_cmd $EXT_TEST_IP "mv /tmp/server.log $log_name"
    rc=$(( $rc + $? ))
    _ssh_cmd $EXT_TEST_IP "sudo rm -rf /tmp/.org.chromium.Chromium.*"
    return $rc
}

test_server_restart() {
    NODE=$(echo $INT_CLUSTER_IPS | cut -d ',' -f1)

    bg_ssh_cmd $EXT_TEST_IP "bash -c 'nohup python ./server.py -t $NODE 2>&1 > /tmp/server.log </dev/null &'"
}

parse_args "$@"

task "Testing cluster"

ssh_ping $EXT_TEST_IP || die 1 "Cannot contact test host $EXT_TEST_IP"
pssh_ping $EXT_CLUSTER_IPS || die 1 "Cannot contact one or more of cluster hosts $EXT_CLUSTER_IPS"

task "Checking test server status"
if [ -n "$SERVER_KILL" ]; then
  echo "Killing server"
  test_server_cleanup
  TEST_SERVER_STATUS=$?
else
  test_server_check
  TEST_SERVER_STATUS=$?
fi

if [ $TEST_SERVER_STATUS -ne 0 ]; then
    task "Restarting test server"
    test_server_restart || die 1 "Cannot restart test server"
    echo "Test server restarted. Waiting for 20 seconds."
    sleep 20
else
    echo "Test server running"
fi

task "Starting UI Test Suite"
UI_TEST_PORT=5909
NODES=($(echo $INT_CLUSTER_IPS | sed -e 's/,/\n/g'))
NUM_USERS_LIMIT=2
MODE=ten

test_users=0
for NODE in "${NODES[@]}"; do
    #NUM_USERS=$(( 2 + $RANDOM%3 )) # 2-4 users
    NUM_USERS=1
    UI_RUN_TEST_URL="https://${EXT_TEST_IP}:${UI_TEST_PORT}/action?name=start&mode=${MODE}&timeDilation=${TIME_DILATION}&host=${NODE}&server=${INT_TEST_IP}&port=${UI_TEST_PORT}&users=${NUM_USERS}"
    run_gui_test_cmd "$UI_RUN_TEST_URL" || die 1 "failed to start GUI TEST"
    test_users=$(( $test_users + $NUM_USERS ))

    [ -n "$SERVER_NOT_RESPONDING" ] && test_server_cleanup && die 1 "server not responding"

    if [ $test_users -ge $NUM_USERS_LIMIT ]; then
        break
    fi
done

[ -n "$START_ONLY" ] && exit 0

elapsed=0
UI_TEST_STATUS_URL="https://${EXT_TEST_IP}:${UI_TEST_PORT}/action?name=getstatus"
while :
do
    echo "UI Test is running"
    sleep 5
    elapsed=$(( $elapsed + 5 ))
    run_gui_test_cmd "$UI_TEST_STATUS_URL" || die 1 "failed to get GUI TEST status"
    UI_TEST_STATUS=$(echo $RETVAL | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$UI_TEST_STATUS" != "Still running" ]; then
        echo "TEST STATUS: $UI_TEST_STATUS"
        break
    fi

    if [ $elapsed -ge 300 ]; then
        echo "Test timed out"
        break
    fi
done

echo "UI Test has stopped"
echo "$RETVAL"

task "Shutting down test server"
[ -n "$SERVER_NOT_RESPONDING" ] && test_server_cleanup && die 1 "server not responding"

UI_TEST_CLOSE_URL="https://${EXT_TEST_IP}:${UI_TEST_PORT}/action?name=close"
run_gui_test_cmd "$UI_TEST_CLOSE_URL" || die 1 "failed to close GUI TEST"
ARCH_LOG_NAME="/tmp/server.log.$$.${RANDOM}"
test_server_cleanup "$ARCH_LOG_NAME"

if [[ "$RETVAL" == *"status:fail"* ]]; then
  FAILED_LOG="${TMPDIR}/ui-server.$$.${RANDOM}.log"
  scp_cmd "${EXT_TEST_IP}:${ARCH_LOG_NAME}" "$FAILED_LOG"
  cat "$FAILED_LOG" >&2
  rm -f "$FAILED_LOG"
  FAIL_MSG="[0] [FAILURE] TEST SUITE FAILED"
  [ -n "$IGNORE_UI_TEST" ] && [ "$IGNORE_UI_TEST"=="1" ] && \
      echo "$FAIL_MSG" && exit 0
  die 1 "$FAIL_MSG"
else
  echo "[0] [SUCCESS] TEST SUITE PASS"
fi
