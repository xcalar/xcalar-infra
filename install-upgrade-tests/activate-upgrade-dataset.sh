#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

SESSION_REPLAY_SCRIPT="${SESSION_REPLAY_SCRIPT:-session-replay-test.py}"

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

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

parse_args "$@"

NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
ssh_ping $NODE_ZERO

task "Copying replay test script to $NODE_ZERO"
scp_cmd "$DIR/${SESSION_REPLAY_SCRIPT}" "${NODE_ZERO}:/tmp" || die "Unable to copy $UPGRADE_DATA_FILE to $NODE_ZERO"

task "Replaying the stored workbook"
ssh_cmd "$NODE_ZERO" "XLRDIR=\${XLRDIR:-/opt/xcalar} PYTHONPATH=\$XLRDIR/lib/python2.7/pyClient.zip:$PYTHONPATH  /opt/xcalar/bin/python2.7 /tmp/${SESSION_REPLAY_SCRIPT}" || die "Unable to run ${SESSION_REPLAY_SCRIPT} on $NODE_ZERO"
