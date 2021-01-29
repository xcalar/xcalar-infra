#!/bin/bash

CLUSTER="${1:-`whoami`-xcalar}"

say () {
    echo >&2 "$*"
}

die () {
    say "ERROR: $*"
    exit 1
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    die "usage: $0 <cluster (default: `whoami`-xcalar)>"
fi

if ! aws cloudformation delete-stack --stack-name ${CLUSTER}; then
    res=$?
    if [ $res -ne 0 ]; then
        die "Failed to delete aws cloudformation stack"
    fi
fi

if ! aws cloudformation wait stack-delete-complete --stack-name ${CLUSTER} &>/dev/null; then
    res=$?
    if [ $res -ne 0 ]; then
        die "Timed out waiting for aws cloudformation stack to delete"
    fi
fi
