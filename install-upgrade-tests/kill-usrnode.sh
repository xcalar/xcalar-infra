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
    say "-i - input file describing the cluster"
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

task "Testing cluster"

hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
cluster_size=${#hosts_array[@]}

kill_node=$(( $RANDOM%$cluster_size ))

task "Killing node number $kill_node"

_ssh_cmd "${hosts_array[$kill_node]}" "pkill -9 -f usrnode"

echo "[0] [SUCCESS] Killed."
