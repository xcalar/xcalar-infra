#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

EXPECTED_RC=${EXPECTED_RC:-0}
EXPECTED_RC2=$(( $EXPECTED_RC + 2 ))

usage() {
    say "usage: $0 [-h|--help]  [-t <test name>] -i <input file> -d -f <test JSON file>"
    say "-r - expected return code"
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
            -r)
                EXPECTED_RC=$1
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
    BUILD_USERNAME=$(jq -r ".InstallUsername" $TEST_FILE)
    INACTIVE_SERVICES=$(jq -r ".InstallerFile.InactiveServices" $TEST_FILE)

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

parse_args "$@"

parse_test_file

NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))

remote_path="PATH=${INSTALL_DIR}/opt/xcalar/bin:/sbin:/usr/sbin:\$PATH XCE_WORKDIR=${INSTALL_DIR}/var/tmp/${BUILD_USERNAME}-root XCE_LOGDIR=${INSTALL_DIR}/var/log"

task "Checking Xcalar status"
n=0
anyfailed=0
pids=()
for host in "${hosts_array[@]}"; do
    OUTDIR="${TMPDIR}/${n}"
    mkdir -p "$OUTDIR"
    case "${CLOUD_PROVIDER}" in
        aws)
            ssh $SSH_DEBUG -tt -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking no" -o "ServerAliveInterval 5" $AWS_SSH_OPT ${AWS_USER}@$host "${remote_path} ${INSTALL_DIR}/opt/xcalar/bin/xcalarctl status" >"$OUTDIR/stdout" 2>"$OUTDIR/stderr" </dev/null &
            ;;
        gce)
            ssh -tt -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking no" -o "ServerAliveInterval 5" $host "${remote_path} ${INSTALL_DIR}/opt/xcalar/bin/xcalarctl status" >"$OUTDIR/stdout" 2>"$OUTDIR/stderr" </dev/null &
            ;;
    esac

    pids+=($!)
    n=$(( $n + 1 ))
done
n=0
for pid in "${pids[@]}"; do
    wait $pid
    rc=$?
    if [ $rc -ne $EXPECTED_RC ] && [ $rc -ne $EXPECTED_RC2 ]; then
        echo "[$n] [FAILURE] Unexpected service status on ${hosts_array[$n]}"
        cat $OUTDIR/std* >&2
        anyfailed=1
    fi
    n=$(( $n + 1 ))
done

[ $anyfailed -ne 0 ] && exit $anyfailed

echo "[0] [SUCCESS] Xcalar is running on all nodes"

task "Checking the number of services managed by supervisord"

exclude_services_cmd=""
for service in $(echo $INACTIVE_SERVICES | sed -e 's/,/ /g'); do
    test -z "$exclude_services_cmd" && exclude_services_cmd="grep -v $service |" || exclude_services_cmd="$exclude_services_cmd grep -v $service |"
done

_ssh_cmd "$NODE_ZERO" "grep -E '^\[program' ${INSTALL_DIR}/etc/xcalar/supervisor.conf | $exclude_services_cmd wc -l"
rc=$?
if [ $rc -eq 0 ]; then
    EXPECTED_RUNNING=$(cat "$TMPDIR/stdout" | tr -d '\r' | tr -d '\n')
else
    echo "[0] [FAILURE] Unexpected failure [rc=${rc}] reading ${INSTALL_DIR}/etc/xcalar/supervisor.conf on $NODE_ZERO"
    cat ${TMPDIR}/std* >&2
    exit 1
fi
echo "[0] [SUCCESS] Number of managed services is $EXPECTED_RUNNING"

task "Checking if managed services are running"
n=0
anyfailed=0
pids=()
for host in "${hosts_array[@]}"; do
    OUTDIR="${TMPDIR}/${n}"
    case "${CLOUD_PROVIDER}" in
        aws)
            ssh $SSH_DEBUG -tt -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking no" $AWS_SSH_OPT "${AWS_USER}@${host}" "${remote_path} supervisorctl -c ${INSTALL_DIR}/etc/xcalar/supervisor.conf status" >"$OUTDIR/stdout" 2>"$OUTDIR/stderr" </dev/null &
            ;;
        gce)
            ssh -tt -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking no" $host "${remote_path} supervisorctl -c ${INSTALL_DIR}/etc/xcalar/supervisor.conf status" >"$OUTDIR/stdout" 2>"$OUTDIR/stderr" </dev/null &

            ;;
    esac

    pids+=($!)
    n=$(( $n + 1 ))
done
n=0
for pid in "${pids[@]}"; do
    wait $pid
    rc=$?
    OUTDIR="${TMPDIR}/${n}"
    if [ $rc -ne 0 ]; then
        echo "[$n] [FAILURE] Unexpected service status [rc=${rc}] on ${hosts_array[$n]}"
        cat $OUTDIR/std* >&2
        anyfailed=1
    else
        run_count_cmd="cat $OUTDIR/stdout | grep RUNNING | $exclude_services_cmd wc -l"
        RUNNING=$(eval "$run_count_cmd")
        if [ "$RUNNING" != "$EXPECTED_RUNNING" ]; then
            echo "[$n] [FAILURE] one or more service failures [rc=${rc}] on ${hosts_array[$n]}"
            cat $OUTDIR/std* >&2
            anyfailed=1
        fi
    fi
    n=$(( $n + 1 ))
done

[ $anyfailed -eq 0 ] && echo "[0] [SUCCESS] All services are running"

exit $anyfailed
