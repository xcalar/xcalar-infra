#!/bin/bash
#
# Spin up a GCE VM to act as a NFS server with
# shared storage on local NVME disk (375Gb)

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
    say "$0 [-f|--force] [-n server-name (default: $NAME)]"
    exit 1
}

while getopts "hfn:" opt "$@"; do
    case "$opt" in
        f) FORCE=true ;;
        h) usage ;;
        n) NAME="$OPTARG" ;;
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

set -e
gcloud compute instances create "${NAME}" "$@" \
    --image-project=${IMAGE_PROJECT} \
    --image-family=${IMAGE_FAMILY} \
    --machine-type=${INSTANCE_TYPE} \
    --boot-disk-type=pd-ssd \
    --boot-disk-size=32GB \
    --local-ssd=interface=NVME \
    --network=${NETWORK} \
    --metadata "cluster=$CLUSTER,owner=$WHOAMI,email=$EMAIL" \
    --metadata-from-file=startup-script=$DIR/../bin/nfs-server.sh

until gcloud compute ssh "${NAME}" --command "mountpoint -q /srv/share"; do
    echo "Waiting for instance to mount local disk ..."
    sleep 10
done
gcloud compute ssh "${NAME}" --command "sudo mkdir -p -m 0777 /srv/share/nfs/cluster/${CLUSTER}"
