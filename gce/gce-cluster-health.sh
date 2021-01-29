#!/bin/bash
export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}

say() {
    echo >&2 "$*"
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "usage: $0 <count (default: 3)> <cluster (default: $(whoami)-xcalar)>" >&2
    exit 1
fi
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPDIR="${TMPDIR:-/tmp}"/gce-cluster-health-$(id -u)/$$
mkdir -p "$TMPDIR"
COUNT="${1:-3}"
CLUSTER="${2:-$(whoami)-xcalar}"
CONFIG="$TMPDIR"/$CLUSTER-config.cfg
UPLOADLOG="$TMPDIR"/$CLUSTER-manifest.log
WHOAMI="$(whoami)"
EMAIL="$(git config user.email)"
INSTANCES=($(
    set -o braceexpand
    eval echo $CLUSTER-{1..$COUNT}
))

PIDS=()
NODENUM=0

for host in "${INSTANCES[@]}"; do
    gcloud compute ssh "$host" --command "grep 'All nodes now network ready' /var/log/xcalar/node.$NODENUM.err" </dev/null &
    PIDS+=($!)
    ((NODENUM++))
done
ret=0
for pid in "${PIDS[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        ret=1
    fi
done
rm -rf "$TMPDIR"
exit $ret
