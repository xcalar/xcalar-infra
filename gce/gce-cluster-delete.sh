#!/bin/bash

export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}

CLUSTER="${CLUSTER:-$(id -un)-xcalar}"
SLEEP="${SLEEP:-10}"
FORCE=false

say() {
    echo >&2 "$*"
}

usage() {
    say "$0 [-a|--all-disks] [-f|--force] cluster-name (default: $CLUSTER)"
    exit 1
}

warn_user() {
    local sleep_delay="${1}"
    local delay
    shift
    say
    say "WARNING: Deleting the following instances! Press Ctrl-C to abort. Sleeping for ${sleep_delay}s."
    say
    say "$*"
    say
    for delay in $(seq ${sleep_delay} -1 1); do
        printf "%d ...\r" $delay >&2
        sleep 1
    done
}

ARGS=()
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -f | --force) FORCE=true ;;
        -a | --all-disks) ARGS+=(--delete-disks=all) ;;
        -h | --help) usage ;;
        -*)
            say "Invalid option: $cmd"
            usage
            ;;
        *)
            CLUSTER="$cmd"
            break
            ;;
    esac
done

set +e

INSTANCES=($(gcloud compute instances list | awk '$1~/^'$CLUSTER'-[0-9]+/{print $1}'))

if [ "${#INSTANCES[@]}" -eq 0 ]; then
    say "No instances found for cluster $CLUSTER"
else
    if ! $FORCE; then
        warn_user "${SLEEP}" "${INSTANCES[@]}"
    fi
    say "Deleting ${INSTANCES[*]} ..."
    gcloud compute instances delete -q "${INSTANCES[@]}" "${ARGS[@]}"
fi

DISKS=($(gcloud compute disks list | awk '$1~/^'$CLUSTER'-swap-[0-9]+/{print $1}'))
DISKS+=($(gcloud compute disks list | awk '$1~/^'$CLUSTER'-data-[0-9]+/{print $1}'))
DISKS+=($(gcloud compute disks list | awk '$1~/^'$CLUSTER'-serdes-[0-9]+/{print $1}'))
if [ "${#DISKS[@]}" -gt 0 ]; then
    say "** Deleting disks. Please ignore any errors **"
    gcloud compute disks delete -q "${DISKS[@]}"
fi
