#!/bin/bash

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

die () {
    echo >&2 "ERROR: $*"
    exit 1
}

HOST="${HOST:-all}"
CLUSTER="${CLUSTER:-`id -un`-xcalar}"

usage() {
    cat << EOF
    usage: $0 [-c cluster (default: `id -un`-xcalar)] [-n hostname (default: $HOST)] -- <optional: ssh-options> ssh-command

EOF
    exit 1
}

while getopts "hn:c:" opt "$@"; do
    case "$opt" in
        h) usage;;
        n) HOST="$OPTARG";;
        c) CLUSTER="$OPTARG";;
        --) break;;
        *) echo >&2 "Unknown option $opt"; usage;;
    esac
done

shift $((OPTIND-1))


TMPDIR="${TMPDIR:-/tmp}/$LOGNAME/azure-cluster/$$"
mkdir -p "$TMPDIR" || die "Failed to create $TMPDIR"
trap "rm -rf $TMPDIR" EXIT

if [ ! -e ~/.ssh/id_azure ]; then
    cp /netstore/infra/azure/id_azure ~/.ssh/
    chmod 0400 ~/.ssh/id_azure
fi

$XLRINFRADIR/azure/azure-cluster-info.sh "$CLUSTER" > "$TMPDIR/hosts.txt"
ii=1
while read hostname; do
    echo "Host $CLUSTER-$ii $hostname"
    echo "  Hostname $hostname"
    echo "  User azureuser"
    echo "  ForwardAgent yes"
    echo "  PubKeyAuthentication yes"
    echo "  PasswordAuthentication no"
    echo "  StrictHostKeyChecking no"
    echo "  UserKnownHostsFile /dev/null"
    echo "  LogLevel ERROR"
    echo "  IdentityFile ~/.ssh/id_azure"
    ii=$(( $ii + 1 ))
done < "$TMPDIR/hosts.txt" > "$TMPDIR/ssh_config"

declare -a HOSTS=($(awk '/^Host/{print $3}' "$TMPDIR/ssh_config"))

test "${#HOSTS[@]}" -gt 0 || die "No RUNNING hosts found matching ${CLUSTER}-\\d+"

#pssh -O StrictHostKeyChecking=no -O UserKnownHostsFile=/dev/null -O LogLevel=ERROR -i -H "${HOSTS[*]}" "$@"
PIDS=()
SKIPPED=()
for hostn in "${HOSTS[@]}"; do
    if [ "$HOST" = "all" -o "$hostn" = "$HOST" ]; then
        mkdir -p "$TMPDIR/$hostn"
        ssh -F "$TMPDIR/ssh_config" "$hostn" "$@" 2> "$TMPDIR/$hostn/err.txt" 1> "$TMPDIR/$hostn/out.txt" </dev/null &
        PIDS+=($!)
        SKIPPED+=("0")
    else
        PIDS+=(-1)
        SKIPPED+=("1")
    fi
done

any_failure=0
RES=()
for idx in `seq 0 $((${#HOSTS[@]} - 1)) `; do
    if [ "${SKIPPED[$idx]}" = "1" ]; then
        continue
    fi

    hostn="${HOSTS[$idx]}"
    wait "${PIDS[$idx]}"
    res=$?
    if [ $res -ne 0 ]; then
        any_failure=1
        echo "## $hostn (ERROR: $res)"
    elif [ "$HOST" = "all" ]; then
        echo "## $hostn"
    fi
    RES+=($res)
    cat "$TMPDIR/$hostn/err.txt" >&2
    cat "$TMPDIR/$hostn/out.txt"
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
