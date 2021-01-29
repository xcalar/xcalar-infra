#!/bin/bash
export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}
GCLOUD_SDK_URL="https://sdk.cloud.google.com"

if [ "$(uname -s)" = Darwin ]; then
    readlink_f() {
        (
            target="$1"

            cd "$(dirname $target)"
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

say() {
    echo >&2 "$*"
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    say "usage: $0 <installer-url>|--no-installer <count (default: 3)> <cluster (default: $(whoami)-xcalar)>"
    exit 1
fi
export PATH="$PATH:$HOME/google-cloud-sdk/bin"
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPDIR="${TMPDIR:-/tmp/$(id -u)}/$(basename ${BASH_SOURCE[0]} .sh)"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"
if [ "$1" == "--no-installer" ]; then
    INSTALLER="$TMPDIR/noop-installer"
    cat <<EOF >$INSTALLER
#!/bin/bash

echo "Done."

exit 0
EOF
    chmod 755 $INSTALLER
elif test -f "$1"; then
    INSTALLER="$(readlink_f ${1})"
elif [[ $1 =~ ^http[s]?:// ]]; then
    INSTALLER="$1"
else
    say "Can't find the installer $1"
    exit 1
fi
INSTALLER_FNAME="$(basename $INSTALLER)"
COUNT="${2:-3}"
CLUSTER="${3:-$(whoami)-xcalar}"
CONFIG=/tmp/$CLUSTER-config.cfg
UPLOADLOG=/tmp/$CLUSTER-manifest.log
WHOAMI="$(whoami)"
EMAIL="$(git config user.email)"
XC_DEMO_DATASET_DIR="${XC_DEMO_DATASET_DIR:-/srv/datasets}"
DISK_TYPE="${DISK_TYPE:-pd-standard}"
NETWORK="${NETWORK:-private}"
INSTANCE_TYPE=${INSTANCE_TYPE:-n1-highmem-8}
IMAGE="${IMAGE:-ubuntu-1404-lts-1485895114}"
INSTANCES=($(
    set -o braceexpand
    eval echo $CLUSTER-{1..$COUNT}
))
SWAP_DISKS=($(
    set -o braceexpand
    eval echo ${CLUSTER}-swap-{1..$COUNT}
))
DATA_DISKS=($(
    set -o braceexpand
    eval echo ${CLUSTER}-data-{1..$COUNT}
))
DATA_SIZE="${DATA_SIZE:-10}"

if [ -z "$DISK_SIZE" ]; then
    case "$INSTANCE_TYPE" in
        n1-highmem-16)
            DISK_SIZE=400
            RAM_SIZE=104
            ;;
        n1-highmem-8)
            DISK_SIZE=200
            RAM_SIZE=52
            ;;
        n1-standard*)
            DISK_SIZE=80
            RAM_SIZE=16
            ;;
        g1-*)
            DISK_SIZE=80
            RAM_SIZE=16
            ;;
        *)
            DISK_SIZE=80
            RAM_SIZE=16
            ;;
    esac
fi

SWAP_SIZE=${SWAP_SIZE:-$RAM_SIZE}

if ! command -v gcloud; then
    if test -e "$XLRDIR/bin/gcloud-sdk.sh"; then
        say "gcloud command not found, attemping to install via $XLRDIR/bin/gcloud-sdk.sh ..."
        bash "$XLRDIR/bin/gcloud-sdk.sh"
        if [ $? -ne 0 ]; then
            say "Failed to install gcloud sdk..."
            exit 1
        fi
    else
        echo "\$XLRDIR/bin/gcloud-sdk.sh not found, attempting to install from $GCLOUD_SDK_URL ..."
        export CLOUDSDK_CORE_DISABLE_PROMPTS=1
        set -o pipefail
        curl -sSL $GCLOUD_SDK_URL | bash -e
        if [ $? -ne 0 ]; then
            say "Failed to install gcloud sdk..."
            exit 1
        fi
        set +o pipefail
    fi
fi

if test -f "$INSTALLER"; then
    if [[ $INSTALLER =~ '/debug/' ]]; then
        INSTALLER_URL="repo.xcalar.net/builds/debug/$INSTALLER_FNAME"
    elif [[ $INSTALLER =~ '/prod/' ]]; then
        INSTALLER_URL="repo.xcalar.net/builds/prod/$INSTALLER_FNAME"
    else
        INSTALLER_URL="repo.xcalar.net/builds/$INSTALLER_FNAME"
    fi
    if ! gsutil ls gs://$INSTALLER_URL &>/dev/null; then
        say "Uploading $INSTALLER to gs://$INSTALLER_URL"
        until gsutil -m -o GSUtil:parallel_composite_upload_threshold=100M \
            cp -c -L "$UPLOADLOG" \
            "$INSTALLER" gs://$INSTALLER_URL; do
            sleep 1
        done
        mv $UPLOADLOG $(basename $UPLOADLOG .log)-finished.log
    else
        say "$INSTALLER_URL already exists. Not uploading."
    fi
    INSTALLER=http://${INSTALLER_URL}
fi

if [[ ${INSTALLER} =~ ^http:// ]]; then
    if ! curl -Is "${INSTALLER}" | head -n 1 | grep -q '200 OK'; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
elif [[ ${INSTALLER} =~ ^gs:// ]]; then
    if ! gsutil ls "${INSTALLER}" &>/dev/null; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
else
    say "WARNING: Unknown protocol ${INSTALLER}"
fi

rm -f $CONFIG
# if CONFIG_TEMPLATE isn't set, use the default template.cfg
CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-$DIR/../bin/template.cfg}"
$DIR/../bin/genConfig.sh $CONFIG_TEMPLATE $CONFIG "${INSTANCES[@]}"

ARGS=()
if [ -n "$IMAGE_FAMILY" ]; then
    ARGS+=(--image-family $IMAGE_FAMILY)
fi

if [ -n "$IMAGE_PROJECT" ]; then
    ARGS+=(--image-project $IMAGE_PROJECT)
fi

if [ -n "$IMAGE" ]; then
    ARGS+=(--image $IMAGE)
fi

if [ $COUNT -gt 3 ]; then
    NOTPREEMPTIBLE="${NOTPREEMPTIBLE:-1}"
fi

if [ "$NOTPREEMPTIBLE" != "1" ]; then
    ARGS+=(--preemptible)
fi

if [ -n "$SUBNET" ]; then
    ARGS+=(--subnet=${SUBNET})
fi

STARTUP_ARGS=()
if [ "$1" != "--no-installer" ]; then
    STARTUP_ARGS+=(--metadata-from-file)
    STARTUP_ARGS+=(startup-script=$DIR/gce-userdata.sh,config=$CONFIG)
fi

say "Launching ${#INSTANCES[@]} instances: ${INSTANCES[*]} .."
set -x
gcloud compute disks create --size=${SWAP_SIZE}GB --type=pd-ssd "${SWAP_DISKS[@]}"
gcloud compute disks create --size=${DATA_SIZE}GB --type=pd-ssd "${DATA_DISKS[@]}"
gcloud compute instances create "${INSTANCES[@]}" "${ARGS[@]}" \
    --machine-type ${INSTANCE_TYPE} \
    --network=${NETWORK} \
    --boot-disk-type $DISK_TYPE \
    --boot-disk-size ${DISK_SIZE}GB \
    --metadata "installer=$INSTALLER,count=$COUNT,cluster=$CLUSTER,owner=$WHOAMI,email=$EMAIL" \
    --tags=http-server,https-server "${STARTUP_ARGS[@]}" | tee $TMPDIR/gce-output.txt
res=${PIPESTATUS[0]}
if [ "$res" -ne 0 ]; then
    exit $res
fi
gcloud compute ssh nfs --command "sudo rm -rf /srv/share/nfs/cluster/$CLUSTER"
for ii in $(seq 1 $COUNT); do
    instance=${CLUSTER}-${ii}
    swap=${CLUSTER}-swap-${ii}
    gcloud compute instances attach-disk $instance --disk=$swap
    gcloud compute instances attach-disk $instance --disk=${CLUSTER}-data-${ii}
    gcloud compute instances set-disk-auto-delete $instance --disk=$swap
done
for ii in $(seq 1 $COUNT); do
    gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo mkswap -f /dev/sdb >/dev/null" \
        && gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "echo /dev/sdb none   swap    sw  0  0 | sudo tee -a /etc/fstab >/dev/null" \
        && gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo swapon /dev/sdb >/dev/null"
    gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo mkfs.ext4 -F /dev/sdc >/dev/null" \
        && gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "echo /dev/sdc $XC_DEMO_DATASET_DIR   ext4 relatime 0  0 | sudo tee -a /etc/fstab >/dev/null" \
        && gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo mkdir -p $XC_DEMO_DATASET_DIR && sudo mount $XC_DEMO_DATASET_DIR"
    gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo mkdir -p /etc/apache2/ssl && curl -sSL http://repo.xcalar.net/XcalarInc_RootCA.crt | sudo tee /etc/apache2/ssl/ca.pem >/dev/null"
    gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "echo export XC_DEMO_DATASET_DIR=$XC_DEMO_DATASET_DIR | sudo tee -a /etc/default/xcalar"
    gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "echo export XCE_MONITOR=1 | sudo tee -a /etc/default/xcalar"
done

if [ "$NOTPREEMPTIBLE" != "1" ]; then
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #internal\n",$5,$1;}' | tee $TMPDIR/hosts-int.txt
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #external\n",$6,$1;}' | tee $TMPDIR/hosts-ext.txt
else
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #internal\n",$4,$1;}' | tee $TMPDIR/hosts-int.txt
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #external\n",$5,$1;}' | tee $TMPDIR/hosts-ext.txt
fi
