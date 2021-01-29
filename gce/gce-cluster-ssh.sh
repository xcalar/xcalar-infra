#!/bin/bash

die() {
    echo >&2 "ERROR: $*"
    exit 1
}

if [ -z "$1" ]; then
    echo >&2 "usage: $0 <cluster (default: $(whoami)-xcalar)> <optional: ssh-options> ssh-command"
    exit 1
fi

if [ -n "$1" ]; then
    CLUSTER="${1}"
    shift
else
    CLUSTER="$(whoami)-xcalar"
fi

TMPDIR="${TMPDIR:-/tmp}/gce-cluster-$(id -u)/$$"
mkdir -p "$TMPDIR" || die "Failed to create $TMPDIR"
trap "rm -rf $TMPDIR" EXIT

gcloud compute instances list --filter="name ~ ${CLUSTER}-\\d+" | grep RUNNING | awk '{printf "%s	    %s\n",$(NF-1),$1}' >"$TMPDIR/hosts.txt"
while read ip hostn; do
    echo "Host $hostn"
    echo "  Hostname $ip"
    echo "  StrictHostKeyChecking no"
    echo "  UserKnownHostsFile /dev/null"
    echo "  LogLevel ERROR"
done <"$TMPDIR/hosts.txt" >"$TMPDIR/ssh_config"

declare -a HOSTS=($(awk '/^Host/{print $2}' "$TMPDIR/ssh_config"))
NHOSTS="${#HOSTS[@]}"
NHOSTS_MINUS_1=$(( NHOSTS - 1 ))

test "$NHOSTS" -gt 0 || die "No RUNNING hosts found matching ${CLUSTER}-\\d+"

if test -z "$SSH_AUTH_SOCK"; then
    eval $(ssh-agent)
fi

if test -n "$SSH_AUTH_SOCK" && test -w "$SSH_AUTH_SOCK"; then
    if ! ssh-add -l | grep -q 'google_compute_engine'; then
        test -f ~/.ssh/google_compute_engine && ssh-add ~/.ssh/google_compute_engine
    fi
fi

echo >&2 "Found $NHOSTS hosts: ${HOSTS[*]}"

#pssh -O StrictHostKeyChecking=no -O UserKnownHostsFile=/dev/null -O LogLevel=ERROR -i -H "${HOSTS[*]}" "$@"
PIDS=()
for hostn in "${HOSTS[@]}"; do
    mkdir -p "$TMPDIR/$hostn"
    ssh -F "$TMPDIR/ssh_config" "$hostn" "$@" 2>"$TMPDIR/$hostn/err.txt" 1>"$TMPDIR/$hostn/out.txt" </dev/null &
    PIDS+=($!)
done

any_failure=0
RES=()
for idx in $(seq 0 $NHOSTS_MINUS_1); do
    hostn="${HOSTS[$idx]}"
    wait "${PIDS[$idx]}"
    res=$?
    if [ $res -ne 0 ]; then
        any_failure=1
        echo "## $hostn (ERROR: $res)"
    else
        echo "## $hostn"
    fi
    RES+=($res)
    cat "$TMPDIR/$hostn/err.txt" >&2
    cat "$TMPDIR/$hostn/out.txt"
done
if test $any_failure -gt 0; then
    printf "FAILED: "
    for idx in $(seq 0 $NHOSTS_MINUS_1); do
        hostn="${HOSTS[$idx]}"
        printf '%s ' "$hostn"
    done
    echo ""
fi
exit $any_failure
