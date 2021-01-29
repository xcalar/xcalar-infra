#!/bin/bash
#
# Copy files form local host to a cluster

export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}

export PATH="$PATH:$HOME/google-cloud-sdk/bin"
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

WHOAMI="$(whoami)"
EMAIL="$(git config user.email)"
NETWORK="${NETWORK:-private}"
INSTANCE_TYPE=${INSTANCE_TYPE:-n1-highmem-8}
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-1604-lts}"
IMAGE_PROJECT="${IMAGE_PROJECT:-ubuntu-os-cloud}"
CLUSTER="${CLUSTER:-$(id -un)-xcalar}"
NAME="${CLUSTER}-nfs"

say() {
    echo >&2 "$*"
}

usage() {
    say "$0 [-r server regexp] [-s source dir] [-d destdir]"
    say "Example: $0 -s ~/xcalar/src/data/qa/gdelt-small/ -d /tmp/gdelt/ -r 'blim-customer-.*'"
    exit 1
}

die() {
    say "ERROR: $*"
    exit 1
}

test $# -eq 0 && set -- -h

while getopts "hfr:s:d:" opt "$@"; do
    case "$opt" in
        f) FORCE=true ;;
        r) REGEXP="$OPTARG" ;;
        s) SOURCE="$OPTARG" ;;
        d) DEST="$OPTARG" ;;
        h) usage ;;
        --) break ;;
        \?)
            say "Invalid option -$OPTARG"
            exit 1
            ;;
        :)
            say "Option -$OPTARG requires an argument."
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

[ -z "$SOURCE" ] && die "Need to specify -s source"
[ -z "$DEST" ] && die "Need to specify -d dest"
[ -z "$REGEXP" ] && die "Need to specify -r regexp"

set -e

TMPDIR="${TMPDIR:-/tmp}/$LOGNAME/gce-cluster/$$"
mkdir -p "$TMPDIR" || die "Failed to create $TMPDIR"
trap "rm -rf $TMPDIR" EXIT

INSTANCES=($(gcloud compute instances list --filter="status:RUNNING name ~ $REGEXP" | tail -n+2 | awk '{print $1}'))

if [ "${#INSTANCES[@]}" -eq 0 ]; then
    say "No instances found matching $REGEXP"
    exit 1
fi

PIDS=()
for HOST in "${INSTANCES[@]}"; do
    gcloud compute ssh --strict-host-key-checking=no "$HOST" --command="sudo mkdir -p -m 0777 $DEST" &
    PIDS+=($!)
done
wait "${PIDS[@]}"

PIDS=()
for HOST in "${INSTANCES[@]}"; do
    gcloud compute scp --strict-host-key-checking=no --compress --recurse "$SOURCE" "${HOST}:${DEST}" &
    PIDS+=($!)
done
wait "${PIDS[@]}"
