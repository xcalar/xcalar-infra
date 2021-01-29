#!/bin/bash
#
# Formats the given devices and mounts them. This script is intended to be run on
# cloud instances (tested on AWS and Azure) to format/mount locally SSD into a RAID
# device.

MOUNT=/ephemeral/data
SWAPSIZE=$(free -m | awk '/Mem:/{print $2}')
LEVEL=0
SWAPFILE=${MOUNT}/swapfile

cloudid() {
    local dmi_id='/sys/class/dmi/id/sys_vendor'
    local vendor cloud

    if [ -e "$dmi_id" ]; then
        read -r vendor < "$dmi_id"
        case "$vendor" in
            Microsoft\ Corporation) cloud=azure ;;
            Amazon\ EC2) cloud=aws ;;
            Google) cloud=gce ;;
            VMWare*) cloud=vmware ;;
            oVirt*) cloud=ovirt ;;
        esac
    fi
    echo "$cloud"
    test -n "$cloud"
}

cloud="$(cloudid)"
case "$cloud" in
    azure)
        DEVICES=($(ls /dev/disk/by-id/nvme-Microsoft_NVMe_Direct_Disk* 2> /dev/null | grep -v -- -part))
        if [ "${#DEVICES[@]}" -eq 0 ]; then
            DEVICES=($(ls /dev/disk/azure/resource 2> /dev/null))
        fi
        ;;
    aws)
        DEVICES=($(ls /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_* 2> /dev/null | grep -v -- -part))
        ;;
esac

FSTYPE=ext4
MOUNT_OPTIONS='defaults,discard,nobarrier'
MD_CONFIG=/etc/mdadm.conf

usage() {
    cat << EOF >&2
    usage: $0 [-m|--mount directory (default: $MOUNT)]
              [-s|--swapsize swapfile size in MiB (default $SWAPSIZE), or 0 to disable]
              [-l|--level raid-level (default: $LEVEL)]
              [-t|--type filesystem type (default: $FSTYPE)]
              [-o|--options mount options (default: $MOUNT_OPTIONS)]
              [-c|--config mdadm config (default: $MD_CONFIG)]
              -- DEVICES ... (default: $DEVICES)

    Formats the given devices and mounts them. This script is intended to be run on
    cloud instances (tested on AWS and Azure) to format/mount locally SSD into a RAID
    device.

EOF
    exit 1
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -h | --help) usage ;;
        -m | --mount)
            MOUNT="$1"
            SWAPFILE=${MOUNT}/swapfile
            shift
            ;;
        -s | --swapsize)
            SWAPSIZE="$1"
            shift
            ;;
        -l | --level)
            LEVEL="$1"
            shift
            ;;
        -t | --type)
            FSTYPE="$1"
            shift
            ;;
        -o | --options)
            MOUNT_OPTIONS="$1"
            shift
            ;;
        -c | --config)
            MD_CONFIG="$1"
            shift
            ;;
        --) break ;;
    esac
done

set -e

if [ ${#DEVICES[@]} -eq 0 ] && [ $# -gt 0 ]; then
    echo >&2 "!! WARNING: It doesn't appear you're in a cloud environement !!"
    CLOUDY=false
else
    CLOUDY=true
fi

if [ $# -gt 0 ]; then
    DEVICES="$@"
    echo >&2 "!! You have manually specified to use ${DEVICES[@]}."
    if [ -t 0 ]; then
        echo >&2 "Sleeping 10s .. Press Ctrl-C to exit"
        sleep 10
    fi
fi

NDEVICES="${#DEVICES[@]}"
if [ $NDEVICES -eq 0 ]; then
    echo >&2 "ERROR: No devices found or specified"
    usage
fi
PARTS=()
for device in "${DEVICES[@]}"; do
    if test -b "$device"; then
        echo >&2 "Partitioning disk $device"
        parted ${device} -s -- 'mklabel gpt mkpart primary 1 -1'
        PARTS+=(${device}-part1)
    else
        echo >&2 "WARNING: $device doesn't appear to be a valid block device"
    fi
done
partprobe
sync
until test -b ${PARTS[0]}; do
    sleep 2
done

NPARTS="${#PARTS[@]}"
if [ $NPARTS -eq 0 ]; then
    echo >&2 "ERROR: No valid partitions found or specified"
    usage
elif [ $NPARTS -eq 1 ]; then
    PART=${PARTS[0]}
else
    PART=/dev/md0
    mdadm --create ${PART} --force --run --level=${LEVEL} --raid-devices="$NPARTS" "${PARTS[@]}"
fi
until test -b $PART; do
    sleep 2
done
if test -e "$MD_CONFIG"; then
    sed -i '/^# Start of mkraid configuration/,/^# End of mkraid configuration/{d}' "$MD_CONFIG"
else
    touch "$MD_CONFIG"
fi
(
    echo "# Start of mkraid configuration"
    mdadm --detail --scan --verbose
    echo "# End of mkraid configuration"
) | tee -a "$MD_CONFIG"

#
if [ "$FSTYPE" = ext4 ]; then
    mkfs.ext4 -m 0 -L EPHEMERAL -F -E nodiscard $PART >&2
else
    mkfs.$FSTYPE -f $PART >&2
fi

UUID=$(blkid -s UUID $PART -o value)
LABEL=$(blkid -s LABEL $PART -o value)

mkdir -p $MOUNT \
    && mount -t $FSTYPE $PART $MOUNT \
    && echo "UUID=$UUID    $MOUNT      $FSTYPE     ${MOUNT_OPTIONS:-defaults},nofail     0   0 # Added by mkraid"
if [ $? -ne 0 ]; then
    echo >&2 "ERROR: Unexpected error"
    exit 1
fi

if [ -n "$SWAPSIZE" ] && [ "$SWAPSIZE" != 0 ]; then
    case "$FSTYPE" in
        ext*)
            fallocate -l "${SWAPSIZE}M" $SWAPFILE
            ;;
        xfs)
            dd if=/dev/zero of=$SWAPFILE bs=1MiB count=$SWAPSIZE
            ;;
        *)
            echo >&2 "WARNING: Unsupported file system $FSTYPE for swapfiles"
            exit 0
            ;;
    esac
    chmod 0600 $SWAPFILE \
        && mkswap $SWAPFILE \
        && swapon $SWAPFILE \
        && echo "$SWAPFILE     none        swap    sw,nofail           0   0 # Added by mkraid"
fi
dracut --mdadmconf --verbose -f
