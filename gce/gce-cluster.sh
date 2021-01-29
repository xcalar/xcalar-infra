#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

export XLRINFRADIR="${XLRINFRADIR:-$(cd $DIR/.. && pwd)}"
export PATH="${XLRINFRADIR}/bin:${PATH}"

export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}
GCLOUD_SDK_URL="https://sdk.cloud.google.com"
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
    gcloud compute disks delete -q "${SWAP_DISKS[@]}" || true
    gcloud compute disks delete -q "${SERDES_DISKS[@]}" || true
}

die() {
    cleanup
    say "ERROR($1): $2"
    exit $1
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    say "usage: $0 <installer-url>|--no-installer <count (default: 3)> <cluster (default: $(whoami)-xcalar)>"
    exit 1
fi
export PATH="$PATH:$HOME/google-cloud-sdk/bin"
if [ -z "$BUILD_ID" ]; then
    BUILD_ID=$$
fi
TMPDIR="${TMPDIR:-/tmp/$(id -u)}/$(basename ${BASH_SOURCE[0]} .sh)-${BUILD_ID}"
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
CONFIG=$TMPDIR/$CLUSTER-config.cfg
LDAP_CONFIG="http://repo.xcalar.net/ldap/gceLdapConfig.json"
UPLOADLOG=$TMPDIR/$CLUSTER-manifest.log
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
SERDES_DISKS=($(
    set -o braceexpand
    eval echo ${CLUSTER}-serdes-{1..$COUNT}
))
XCE_XDBSERDESPATH="/xcalarSwap"
DATA_DISKS=($(
    set -o braceexpand
    eval echo ${CLUSTER}-data-{1..$COUNT}
))
DATA_SIZE="${DATA_SIZE:-0}"

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
SERDES_SIZE=${SERDES_SIZE:-$SWAP_SIZE}

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
# setting MoneyRescale to false(needed to compare results wit answer set and spark)
CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-$DIR/../bin/template.cfg}"
$DIR/../bin/genConfig.sh $CONFIG_TEMPLATE - "${INSTANCES[@]}" >$CONFIG

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

say "Launching ${#INSTANCES[*]} instances: ${INSTANCES[*]} .."
set -x
gcloud_retry compute disks create "${SWAP_DISKS[@]}" --size=${SWAP_SIZE}GB --type=pd-ssd
res=$?
if [ $res -ne 0 ]; then
    die $res "Failed to create disks"
fi
gcloud_retry compute disks create "${SERDES_DISKS[@]}" --size=${SERDES_SIZE}GB --type=pd-ssd
res=$?
if [ $res -ne 0 ]; then
    die $res "Failed to create disks"
fi
if [ $DATA_SIZE -gt 0 ]; then
    gcloud_retry compute disks create "${DATA_DISKS[@]}" --size=${DATA_SIZE}GB --type=pd-ssd
fi

gcloud_retry compute instances create "${INSTANCES[@]}" "${ARGS[@]}" \
    --machine-type ${INSTANCE_TYPE} \
    --network=${NETWORK} \
    --boot-disk-type $DISK_TYPE \
    --boot-disk-size ${DISK_SIZE}GB \
    --metadata "installer=$INSTALLER,count=$COUNT,cluster=$CLUSTER,owner=$WHOAMI,email=$EMAIL,ldapConfig=$LDAP_CONFIG,license=$XCE_LICENSE" \
    --tags=http-server,https-server "${STARTUP_ARGS[@]}" | tee $TMPDIR/gce-output.txt
res=${PIPESTATUS[0]}
if [ "$res" -ne 0 ]; then
    die $res "Failed to create some instances"
fi
gcloud compute ssh nfs --ssh-flag="-tt" --command 'sudo rm -rf /srv/share/nfs/cluster/'$CLUSTER
for ii in $(seq 1 $COUNT); do
    instance=${CLUSTER}-${ii}
    swap=${CLUSTER}-swap-${ii}
    serdes=${CLUSTER}-serdes-${ii}
    gcloud_retry compute instances attach-disk $instance --disk=$serdes \
        && gcloud_retry compute instances attach-disk $instance --disk=$swap \
        && if [ $DATA_SIZE -gt 0 ]; then
            gcloud_retry compute instances attach-disk $instance --disk=${CLUSTER}-data-${ii}
        fi
    res=$?
    if [ $res -ne 0 ]; then
        die $res "Failed to attach some disks"
    fi
done

# Mount SerDes SSD
disk_setup_script() {
    cat <<-EOF
	#!/bin/bash
	DIR="\$(cd \$(dirname \${BASH_SOURCE[0]}) && pwd)"
	cd \${DIR}
	mkpart() {
	    PART=\${1}1
	    if ! test -b \${PART}; then
	        bash retry.sh parted \$1 -s "mklabel gpt mkpart primary 1 -1"
	        bash retry.sh test -b \${PART}
	    fi
	    echo "\${PART} \$3 \$2 defaults 0 0" | tee -a /etc/fstab
	    case "\$2" in
	        ext4)
	            bash retry.sh mkfs.ext4 -m 0 -F \${PART}
	            bash retry.sh mkdir -p \$3
	            bash retry.sh mount \$3
	            ;;
	        swap)
	            bash retry.sh mkswap -f \${PART}
	            bash retry.sh swapon -v \${PART}
	            ;;
	    esac
	}
	mkpart /dev/sdc swap none
	free -m
	mkpart /dev/sdb ext4 $XCE_XDBSERDESPATH
	chmod o+w $XCE_XDBSERDESPATH
	if [ $DATA_SIZE -gt 0 ]; then
	    bash retry.sh mkdir -p $XC_DEMO_DATASET_DIR
	    mkpart /dev/sdd ext4 $XC_DEMO_DATASET_DIR
	    echo "export XC_DEMO_DATASET_DIR=$XC_DEMO_DATASET_DIR" | tee -a /etc/default/xcalar
	fi
	exit 0
	EOF
}

disk_setup_script >$TMPDIR/disk_setup_script.sh
for ii in $(seq 1 $COUNT); do
    gcloud_retry compute scp $XLRINFRADIR/bin/retry.sh ${CLUSTER}-${ii}:/tmp/retry.sh || die 1 "Failed to copy $XLRINFRADIR/bin/retry.sh to ${CLUSTER}-${ii}"
    gcloud_retry compute scp $TMPDIR/disk_setup_script.sh ${CLUSTER}-${ii}:/tmp/disk_setup_script.sh || die 1 "Failed to copy $TMP/disk_setup_script.sh to ${CLUSTER}-${ii}"
done

FAILED_DISKS=()
for ii in $(seq 1 $COUNT); do
    if ! gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo -H /bin/bash -x /tmp/disk_setup_script.sh"; then
        FAILED_DISKS+=(${ii})
        echo >&2 "Cluster instance ${CLUSTER}-${ii} failed to setup disks properly"
    fi
done

for ii in "${FAILED_DISKS[@]}"; do
    if ! gcloud compute ssh ${CLUSTER}-${ii} --ssh-flag="-tt" --command "sudo -H /bin/bash -x /tmp/disk_setup_script.sh"; then
        die 1 "Cluster instance ${CLUSTER}-${ii} failed to setup disks properly"
    fi
done

if [ "$NOTPREEMPTIBLE" != "1" ]; then
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #internal\n",$5,$1;}' | tee $TMPDIR/hosts-int.txt
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #external\n",$6,$1;}' | tee $TMPDIR/hosts-ext.txt
else
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #internal\n",$4,$1;}' | tee $TMPDIR/hosts-int.txt
    grep 'RUNNING$' $TMPDIR/gce-output.txt | awk '{printf "%s\t%s #external\n",$5,$1;}' | tee $TMPDIR/hosts-ext.txt
fi
