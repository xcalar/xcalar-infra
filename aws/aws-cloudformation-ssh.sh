#!/bin/bash

export AWS_USER=${AWS_USER:-ec2-user}

die () {
    echo >&2 "ERROR: $*"
    exit 1
}

# Will exit on first failure
runClusterCmd() {
    for hostn in "${HOSTS[@]}"; do
        ssh -o ServerAliveInterval=5 "${AWS_USER}@$hostn" "$1"
        ret=$?
        if [ "$ret" != 0 ]; then
            return "$ret"
        fi
    done
    return 0
}

if [ -z "$1" ]; then
    echo >&2 "usage: $0 <cluster (default: `whoami`-xcalar)> <optional: ssh-options> ssh-command"
    exit 1
fi

if [ -n "$1" ]; then
    CLUSTER="${1}"
    shift
else
    CLUSTER="`whoami`-xcalar"
    shift
fi

TMPDIR="${TMPDIR:-/tmp}/$LOGNAME/aws-cloudformation/$$"
mkdir -p "$TMPDIR" || die "Failed to create $TMPDIR"
trap "rm -rf $TMPDIR" EXIT

if [ "$1" = "singleNode" ]; then
    declare -a HOSTS=($(aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=$CLUSTER" | jq -r '.Reservations[].Instances[] | .PublicDnsName' | head -1))
    shift
elif [ "$1" = "runClusterCmd" ]; then
    declare -a HOSTS=($(aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=$CLUSTER" | jq -r '.Reservations[].Instances[] | .PublicDnsName'))
    runClusterCmd "$2"
    exit $?
elif [ "$1" = "host" ]; then
    aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=$CLUSTER" | jq -r '.Reservations[].Instances[] | .PublicIpAddress, .PublicDnsName' | xargs -n2 > "$TMPDIR/hosts.txt"
    ret=$?
    if [ $ret -eq 0 ]; then
        cat  "$TMPDIR/hosts.txt" | head -1 | cut -d " " -f 1
        exit 0
    fi
    exit $ret
else
    declare -a HOSTS=($(aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=$CLUSTER" | jq -r '.Reservations[].Instances[] | .PublicDnsName'))
fi

test "${#HOSTS[@]}" -gt 0 || die "No RUNNING hosts found matching ${CLUSTER}-\\d+"

echo >&2 "Found ${#HOSTS[@]} hosts: ${HOSTS[@]}"

PIDS=()
for hostn in "${HOSTS[@]}"; do
    mkdir -p "$TMPDIR/$hostn"
    touch "$TMPDIR/$hostn/err.txt"
    touch "$TMPDIR/$hostn/out.txt"
    mkdir -p "$TMPDIR/$hostn"
    ssh -o ServerAliveInterval=5 "${AWS_USER}@$hostn" "$@" 2> "$TMPDIR/$hostn/err.txt" 1> "$TMPDIR/$hostn/out.txt" </dev/null &
    PIDS+=($!)
done

any_failure=0
RES=()
for idx in `seq 0 $((${#HOSTS[@]} - 1)) `; do
    hostn="${HOSTS[$idx]}"
    wait "${PIDS[$idx]}"
    res=$?
    if [ $res -ne 0 ]; then
        any_failure=1
        echo "## $hostn (ERROR: $res)"
        ssh "${AWS_USER}@$hostn" ls
    else
        echo "## $hostn"
    fi
    RES+=($res)

    if [ -f "$TMPDIR/$hostn/err.txt" ]; then
        cat "$TMPDIR/$hostn/err.txt" >&2
    fi

    if [ -f "$TMPDIR/$hostn/out.txt" ]; then
        cat "$TMPDIR/$hostn/out.txt"
    fi
done
if test $any_failure -gt 0; then
    printf "FAILED: "
    for idx in `seq 0 $((${#HOSTS[@]} - 1)) `; do
        hostn="${HOSTS[$idx]}"
        printf "$hostn "
    done
    echo ""
fi
exit $any_failure
