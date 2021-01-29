#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] -i <input file> -f <test data path> [-r <xcalar root>]"
    say "-i - input file describing the cluster"
    say "-f - path to file containing upgrade test data set"
    say "-h|--help - this help message"
}

UPGRADE_DATA_PATH=""

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
            -f)
                UPGRADE_DATA_PATH="$1"
                UPGRADE_DATA_FILE=$(basename "$UPGRADE_DATA_PATH")
                shift

                if [ ! -e "$UPGRADE_DATA_PATH" ]; then
                    say "Test config file $UPGRADE_DATA_PATH does not exist"
                    exit 1
                fi
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

    if [ -z "$UPGRADE_DATA_PATH" ]; then
        die 1 "[0] [FAILURE] No upgrade data file specified"
    fi

    if [ -z "$INPUT_FILE" ]; then
        say "No input file specified"
        exit 1
    fi
}

parse_args "$@"

NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
ssh_ping $NODE_ZERO

task "Copying upgrade dataset to cluster"
scp_cmd "$UPGRADE_DATA_PATH" "${NODE_ZERO}:/tmp" || die "Unable to copy $UPGRADE_DATA_FILE to $NODE_ZERO"

task "Finding XcalarRoot on $NODE_ZERO"
find_xce_path "$NODE_ZERO" || die 1 "[0] [FAILURE] Unable to find XCE Root Path"
echo "[0] [SUCCESS] XCE_ROOT_PATH is $XCE_ROOT_PATH"

task "Unpacking upgrade dataset to $XCE_ROOT_PATH"
ssh_cmd "$NODE_ZERO" "tar xzf /tmp/${UPGRADE_DATA_FILE}" -C "$XCE_ROOT_PATH" || die "Unable to unpack ${UPGRADE_DATA_FILE} into $XCE_ROOT_PATH"
