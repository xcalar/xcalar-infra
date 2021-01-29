#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

export XLRINFRADIR="${XLRINFRADIR:-$(cd $DIR/.. && pwd)}"
export PATH="${XLRINFRADIR}/bin:${PATH}"

. gce-sh-lib

export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}
GC_COMMON_OPTIONS="--zone=$CLOUDSDK_COMPUTE_ZONE"

if [ "$(uname -s)" = Darwin ]; then
    readlink_f() {
        (
            set -e
            target="$1"

            cd "$(dirname $target)" || exit 1
            target="$(basename $target)"

            # Iterate down a (possible) chain of symlinks
            while [ -L "$target" ]; do
                target="$(readlink $target)"
                cd "$(dirname $target)"
                target="$(basename $target)"
            done

            echo "$(pwd -P)/$target"
        )
    }
else
    readlink_f() {
        readlink -f "$@"
    }
fi

# duped code with disk_setup_script. should be refactored to be in infra-sh-lib and move disk setup and cloud_retry in
# gce-sh-lib
gcloud_retry() {
    retry.sh gcloud "$@" $GC_COMMON_OPTIONS
}

say() {
    echo >&2 "$*"
}

cleanup() {
    gcloud compute instances delete -q "${INSTANCES[@]}" || true
}

die() {
    cleanup
    say "ERROR($1): $2"
    exit $1
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "usage: [-i <installer-url>|--no-installer] [--image-id IMAGE_ID] [--nfs-share share] [-c|--count <count (default: 3)>] [--cluster <cluster (default: $(whoami)-xcalar)>]"
    echo "      [--disk-size 60] [--disk-type pd-standard] [--local-ssd] [--no-local-ssd] [--nfs-share nfs:/srv/share/nfs/cluster/\$CLUSTER]"
    echo "      [--config config.cfg] [--gpu nvidia-tesla-(p4|t4|v100)] [--gpu-count 1] [--startup-script gce-cloud-init.sh] [--license lic] -- EXTRA_GCLOUD_ARGS"
    exit 0
fi

ARGS=()
export BUILD_ID=${BUILD_ID:-$(date +%s)}
export TMPDIR="${TMPDIR:-/tmp/$(id -u)}/$(basename ${BASH_SOURCE[0]} .sh)-${BUILD_ID}"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-$DIR/../bin/template.cfg}"
COUNT="${COUNT:-3}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DISK_TYPE="${DISK_TYPE:-pd-standard}"
DISK_SIZE=${DISK_SIZE:-60}
NETWORK="${NETWORK:-private}"
LOCAL_SSD=${LOCAL_SSD:-1}
IMAGE_PROJECT=${IMAGE_PROJECT:-$GCE_PROJECT}
PREEMPTIBLE=${PREEMPTIBLE:-0}
GPU_COUNT=1
USER_DATA="${USER_DATA:-$DIR/gce-cloud-init.sh}"
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --cluster) CLUSTER="$1"; shift;;
        --no-installer) unset INSTALLER INSTALLER_URL;;
        --image-family) IMAGE_FAMILY="$1"; shift;;
        --image-project) IMAGE_PROJECT="$1"; shift;;
        -i|--installer) INSTALLER="$1"; shift;;
        --name) NAME="$1"; shift;;
        -c|--count) COUNT="$1"; shift;;
        --machine-type) INSTANCE_TYPE="$1"; shift;;
        --instance-type) INSTANCE_TYPE="$1"; shift;;
        --gpu) GPU="$1"; shift;;
        --gpu-count) GPU_COUNT="$1"; shift;;
        --disk-size) DISK_SIZE="$1"; shift;;
        --disk-type) DISK_TYPE="$1"; shift;;
        --image-id) IMAGE="$1"; shift;;
        --local-ssd) LOCAL_SSD=1;;
        --no-local-ssd) LOCAL_SSD=0;;
        --config-template) test -f "$1" && CONFIG_TEMPLATE="$1" || die "$1 doesn't exist"; shift;;
        --config) test -f "$1" && CONFIG="$1" || die "$1 doesn't exist"; shift;;
        --preemptible) PREEMPTIBLE=1;;
        --user-data) test -f "$1" && USER_DATA="$1" || die "$1 doesn't exist"; shift;;
        --startup-script) test -f "$1" && STARTUP_SCRIPT="$1" || die "$1 doesn't exist"; shift;;
        --license) test -n "$1" && XCE_LICENSE="$1" || die "$1 doesn't exist"; shift;;
        --nfs-share) NFS_SHARE="$1"; shift;;
        --) break ;;
    esac
done

if [ -z "$CLUSTER" ]; then
    die "Must specify cluster name"
fi
if [ -z "$NAME" ]; then
    NAME=$CLUSTER
fi

if [ -z "$IMAGE_FAMILY" ]; then
    if [ -n "$GPU" ]; then
        IMAGE_FAMILY=xcalar-el7-gpu
    else
        IMAGE_FAMILY=xcalar-el7-std
    fi
fi

if [ -z "$INSTANCE_TYPE" ]; then
    if [[ "$*" =~ custom ]]; then
        echo >&2 "INFO: Instance type not specified, using custom settings"
    else
        INSTANCE_TYPE="n1-standard-8"
        echo >&2 "WARN: No --instance-type specified no --custom-* flags. Using $INSTANCE_TYPE"
    fi
elif [[ "$*" =~ custom ]]; then
    echo >&2 "WARN: Specified both --instance-type and --custom-* flags. Removing $INSTANCE_TYPE"
    unset INSTANCE_TYPE
fi

MD_ARGS="name=$NAME,cluster=$CLUSTER"
if [ -e "$USER_DATA" ]; then
    MDF_ARGS+="user-data=$USER_DATA"
    CLOUD_INIT=1
fi
if [ -e "$STARTUP_SCRIPT" ]; then
    MDF_ARGS+="startup-script=$STARTUP_SCRIPT"
fi

if ! test -e "$STARTUP_SCRIPT" && ! test -e "$USER_DATA"; then
    die "Must specify either --startup-script or --user-data"
fi

EMAIL="${BUILD_USER_EMAIL:-$(git config user.email)}"
USERID="${BUILD_USER_ID:-$(id -un)}"
LDAP_CONFIG="http://repo.xcalar.net/ldap/gceLdapConfig.json"
UPLOADLOG=$TMPDIR/$CLUSTER-manifest.log
WHOAMI="$(whoami)"
XC_DEMO_DATASET_DIR="${XC_DEMO_DATASET_DIR:-/srv/datasets}"
INSTANCES=($(
    set -o braceexpand
    eval echo $NAME-{1..$COUNT}
))
XCE_XDBSERDESPATH="/ephemeral/data"

# if CONFIG_TEMPLATE isn't set, use the default template.cfg
# setting MoneyRescale to false(needed to compare results wit answer set and spark)
if ! test -e "$CONFIG"; then
    CONFIG=${TMPDIR}/$CLUSTER-config-$$.cfg
    $DIR/../bin/genConfig.sh $CONFIG_TEMPLATE - "${INSTANCES[@]}" >$CONFIG
fi
if [ -n "$GPU" ]; then
    case "$GPU" in
        nvidia-*) ;;
        *) echo >&2 "ERROR: Invalid gpu selection: $GPU!"; exit 1;;
    esac
    IMAGE_GPU=
    if ! IMAGE_GPU="$(set -o pipefail; gcloud compute images describe-from-family "$IMAGE_FAMILY" --format=json | jq -r .labels.gpu)"; then
        die "Must specify GPU enabled image-family"
    fi
    if [ -z "$IMAGE_GPU" ]; then
        die "Must specify GPU enabled image-family"
    fi
    ARGS+=(--accelerator count=$GPU_COUNT,type=$GPU --maintenance-policy=TERMINATE)
fi

if [ -n "$IMAGE_FAMILY" ]; then
    ARGS+=(--image-family $IMAGE_FAMILY)
fi

if [ -n "$IMAGE_PROJECT" ]; then
    ARGS+=(--image-project $IMAGE_PROJECT)
fi

if [ -n "$IMAGE" ]; then
    ARGS+=(--image $IMAGE)
fi

if [ "$PREEMPTIBLE" = "1" ]; then
    ARGS+=(--preemptible)
fi

if [ -n "$SUBNET" ]; then
    ARGS+=(--subnet ${SUBNET})
fi

if [ -r "$CONFIG" ]; then
    MDF_ARGS+=",config=$CONFIG"
fi
if [ -f "$XCE_LICENSE" ]; then
    MDF_ARGS+=",license=$XCE_LICENSE"
elif [ -n "$XCE_LICENSE" ]; then
    MD_ARGS+=",license=$XCE_LICENSE"
fi

if [ -r "$INSTALLER" ]; then
    if [ -z "$INSTALLER_URL" ]; then
        INSTALLER_URL="$(installer-upload.sh -d gs "$INSTALLER")"
    fi
fi
if [ -n "$INSTALLER_URL" ]; then
    MD_ARGS+=",installer_url=$INSTALLER_URL"
fi
if [ -z "$NFS_SHARE" ]; then
    NFS_SHARE="nfs:/srv/share/nfs/cluster/$CLUSTER"
    gcloud compute ssh nfs --ssh-flag="-tt" --command 'sudo mkdir -m 1777 -p /srv/share/nfs/cluster/'$CLUSTER
fi
if [ "$LOCAL_SSD" != 0 ]; then
    ARGS+=(--local-ssd interface=nvme)
    EPHEMERAL=/ephemeral/data
    MD_ARGS+=",ephemeral_disk=$EPHEMERAL"
    # Constants.XdbMaxPagingFileSize=0
    # Constants.XcalarLogCompletePath=/var/log/xcalar
    # Constants.XdbLocalSerDesPath=/ephemeral/data/serdes
fi

if [ -n "$NFS_SHARE" ]; then
    MD_ARGS+=",nfs=$NFS_SHARE"
fi

say "Launching ${#INSTANCES[*]} instances: ${INSTANCES[*]} .."

gcloud compute instances create "${INSTANCES[@]}" \
    ${INSTANCE_TYPE:+ --machine-type $INSTANCE_TYPE} \
    --boot-disk-type $DISK_TYPE \
    --boot-disk-size ${DISK_SIZE}GB \
    --network $NETWORK \
    --metadata "count=$COUNT,cluster=$CLUSTER,email=$EMAIL,$MD_ARGS" \
    --metadata-from-file "$MDF_ARGS" \
    --tags "http-server,https-server" "${ARGS[@]}" "$@" | tee $TMPDIR/gce-output.txt

    #--metadata "installer=$INSTALLER,count=$COUNT,cluster=$CLUSTER,owner=$WHOAMI,email=$EMAIL,ldapConfig=$LDAP_CONFIG,license=$XCE_LICENSE" \
    #"${STARTUP_ARGS[@]}" | tee $TMPDIR/gce-output.txt
res=${PIPESTATUS[0]}
if [ "$res" -ne 0 ]; then
    die $res "Failed to create some instances"
fi
