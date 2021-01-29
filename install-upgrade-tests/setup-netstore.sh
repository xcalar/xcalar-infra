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

hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))

pssh_cmd "sudo yum -y install nfs-utils"
pssh_cmd "sudo mkdir -p /netstore/datasets"
pssh_cmd "if ! grep netstore /etc/fstab >/dev/null 2>&1; then echo 'nfs:/srv/datasets /netstore/datasets nfs defaults 0 0' | sudo tee -a /etc/fstab; fi"
pssh_cmd "mountpoint -q /netstore/datasets || sudo mount /netstore/datasets"
