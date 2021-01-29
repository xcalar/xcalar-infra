#!/bin/bash

set +e

syslog() {
    logger -i -s -t $(basename $0) "$*"
}

say() {
    echo >&2 "$1"
}

disk_size() {
    local dev blockp size block_size
    # eg, for /dev/disk/azure/resource -> /dev/sdb, dev is sdb
    if ! dev=$(basename $(readlink -f $1)); then
        return 1
    fi
    blockp="/sys/block/${dev}"
    size=$(< $blockp/size)
    block_size=$(< $blockp/queue/hw_sector_size)
    echo $((size * block_size / (1024 * 1024)))
}

cloud_id() {
    if [ "$1" = -f ]; then
        rm -f /run/cloud/*
    fi
    if test -e /run/cloud/id; then
        . /run/cloud/id &&
            cat /etc/cloud/id &&
            return 0
    fi
    rm -f /etc/cloud-id
    mkdir -p /run/cloud-id
    if curl -fsL --connect-timeout 2 -H Metadata:True "http://169.254.169.254/metadata/instance?api-version=2018-02-01&format=json" -o /run/cloud-id/azure.json; then
        CLOUD_ID=azure
        CLOUD_METADATA=/run/cloud-id/${CLOUD_ID}.json
    elif curl -fsL --connect-timeout 2 http://169.254.169.254/2016-09-02/dynamic/instance-identity/document -o /run/cloud-id/aws.json; then
        CLOUD_ID=aws
        CLOUD_METADATA=/run/cloud-id/${CLOUD_ID}.json
    else
        CLOUD_ID=none
    fi
    if [ -n "$CLOUD_ID" ] && [ "$CLOUD_ID" != none ]; then
        echo "CLOUD_ID=$CLOUD_ID" | tee /etc/cloud-id
        echo "CLOUD_METADATA=$CLOUD_METADATA" | tee -a /etc/cloud-id
    fi
}

mdsl() {
    local prop="${1:-compute/vmSize}"
    curl --silent --connect-timeout 2 -s -f -H Metadata:True "http://169.254.169.254/metadata/instance/${prop}?api-version=2018-02-01&format=text"
}

set_defaults() {
    ENABLE_MD=1
    MD_LEVEL=0
    MD_DEVICE=/dev/md0
    MD_CHUNK=64
    MD_CONFIG=/etc/mdadm/mdadm.conf
    ENABLE_SWAP=1
    VG_NAME=ephemeral
    LV_SWAP=swap
    LV_SWAP_SIZE=MEMSIZE2X
    LV_DATA=data
    LV_DATA_EXTENTS=90%FREE
    MOUNT_FSTYPE=ext4
    MOUNT_OPTIONS="defaults,discard,relatime,nobarrier,nodev,nosuid,nofail"
    MOUNT_PATH=/ephemeral/data
    DESTROY_ON_STOP=0
    if [ -r /etc/default/ephemeral-disk ]; then
        . /etc/default/ephemeral-disk
    fi

    if [ -r /etc/sysconfig/ephemeral-disk ]; then
        . /etc/sysconfig/ephemeral-disk
    fi
    LV_DATA_DEV="${LV_DATA_DEV:-/dev/$VG_NAME/$LV_DATA}"
    LV_SWAP_DEV="${LV_SWAP_DEV:-/dev/$VG_NAME/$LV_SWAP}"

}

ephemeral_disks() {
    disks_list=""
    partitions_list=""
    partitions_count=0
    if [ -z "$DISKS" ]; then
        case "$CLOUD_ID" in
        aws) DISKS=$(
            set -o pipefail
            ls /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage* 2> /dev/null | grep -v -- '-part.$'
        ) ;;
        azure) DISKS=$(ls /dev/disk/azure/resource 2> /dev/null) ;;
        none)
            syslog "No cloud. Skipping"
            exit 0
            ;;
        *)
            syslog "Unknown cloud $CLOUD_ID. Skipping"
            exit 0
            ;;
        esac
        if [ $? -ne 0 ] || [ -z "$DISKS" ]; then
            syslog "For CLOUD_ID=$CLOUD_ID, no disks found"
            exit 0
        fi
        syslog "CLOUD_ID=$CLOUD_ID Found DISKS=$DISKS"
    else
        syslog "CLOUD_ID=$CLOUD_ID Using DISKS=$DISKS"
    fi

    for disk in $DISKS; do
        if ! test -b $disk; then
            syslog "Couldn't find disk $disk"
            continue
        fi
        syslog "Considering $disk (${disk}-part1)"
        disks_list="$disks_list $disk"
        partitions_list="$partitions_list ${disk}-part1"
        partitions_count=$((partitions_count + 1))
    done
    disks_list=${disks_list## }
    partitions_list=${partitions_list## }
    if [ -z "$ENABLE_MD" ] || [ "$ENABLE_MD" == 1 ]; then
        [ $partitions_count -gt 1 ] && ENABLE_MD=1 || ENABLE_MD=0
    fi
}

ephemeral_create() {
    ephemeral_disks
    if [ -z "$DISKS" ]; then
        syslog "No disks found"
        exit 0
    fi

    if [ ! -b "$LV_DATA_DEV" ]; then
        say "Wiping disk(s) ${disks_list[*]} ..."
        wipefs -faq ${disks_list[*]}

        for disk in $disks_list; do
            say "Partitioning disk $disk ..."

            if [ "$ENABLE_MD" = "1" ]; then
                say "Enabling partition RAID flag ..."
                parted --align optimal --script "$disk" mklabel gpt mkpart primary ext2 2048s 100% set 1 raid on
            else
                say "Enabling partition LVM flag ..."
                parted --align optimal --script "$disk" mklabel gpt mkpart primary ext2 2048s 100% set 1 lvm on
            fi

            sleep 2
            say "Probing partitions ..."
            partprobe $disk
            for delay in $(seq 1 4); do
                sleep $delay
                test -b "${disk}-part1" && break
            done
        done
        test -b "${disk}-part1" && wipefs -faq "${disk}-part1"

        if [ "$ENABLE_MD" = "1" ]; then
            say "Creating MD device /dev/md0 ..."
            yes | mdadm --create "$MD_DEVICE" --level="$MD_LEVEL" --chunk="$MD_CHUNK" --raid-devices="$partitions_count" ${partitions_list[*]}

            say "Storing MD device configuration ..."
            mkdir -p $(dirname "$MD_CONFIG")
            touch "$MD_CONFIG"
            sed -i '/^# Begin of ephemeral-scripts configuration/,/^# End of ephemeral-scripts configuration/{d}' "$MD_CONFIG"
            {
                echo "# Begin of ephemeral-scripts configuration"
                mdadm --detail --scan >> "$MD_CONFIG"
                echo "# End of ephemeral-scripts configuration"
            } >> "$MD_CONFIG"

            say "Creating LVM PV $MD_DEVICE ..."
            pvcreate -f "$MD_DEVICE"

            say "Creating LVM VG $VG_NAME ..."
            vgcreate -f "$VG_NAME" "$MD_DEVICE"
        else
            say "Creating LVM PV(s) ${partitions_list[*]} ..."
            pvcreate -fy ${partitions_list[*]}

            say "Creating LVM VG $VG_NAME ..."
            vgcreate -f "$VG_NAME" ${partitions_list[*]}
        fi
        if [ ! -b "$LV_SWAP_DEV" ]; then
            if [ "$ENABLE_SWAP" = "1" ] && [ "$LV_SWAP_SIZE" != 0 ]; then
                MEMSIZE=$(free -m | awk '/Mem:/{print $2}')
                if [ -z "$LV_SWAP_SIZE" ] || [ "$LV_SWAP_SIZE" = MEMSIZE ]; then
                    LV_SWAP_SIZE="${MEMSIZE}M"
                fi
                if [ "$LV_SWAP_SIZE" = MEMSIZE2X ]; then
                    LV_SWAP_SIZE="$((MEMSIZE * 2))M"
                fi

                say "Creating LVM LV $VG_NAME/$LV_SWAP ..."
                lvcreate --yes -L "$LV_SWAP_SIZE" -n "$LV_SWAP" "$VG_NAME"

                say "Formating swap partition ..."
                mkswap -f "$LV_SWAP_DEV"
                sed -i '/ephemeral-swap/d' /etc/fstab
            fi
        fi
        say "Creating LVM LV $VG_NAME/$LV_DATA ..."
        lvcreate --yes -l "$LV_DATA_EXTENTS" -n "$LV_DATA" "$VG_NAME"

        say "Formating data partition ..."
        sh -c "mkfs.$MOUNT_FSTYPE -L $VG_NAME-$LV_DATA -m 0 -F $LV_DATA_DEV"
        sed -i '/ephemeral-data/d' /etc/fstab
    fi

}

ephemeral_destroy() {
    ephemeral_disks

    if [ "$ENABLE_SWAP" == "1" ]; then
        if [ -b "$LV_SWAP_DEV" ]; then
            r_swap=$(realpath -q "$LV_SWAP_DEV")
            for device in $(swapon -s | tail -n +2 | awk '{print $1}'); do
                r_device=$(realpath "$device")
                if [ "$r_device" = "$r_swap" ]; then
                    say "Deactivating swap ..."
                    swapoff "$LV_SWAP_DEV"
                    break
                fi
            done
        fi
    fi

    if [ "$ENABLE_SWAP" == "1" ]; then
        say "Removing LVM LV $VG_NAME/$LV_SWAP ..."
        lvremove -f "$VG_NAME/$LV_SWAP"
    fi

    mountpoint -q $MOUNT_PATH && umount $MOUNT_PATH || true
    if [ -b "$LV_DATA_DEV" ]; then
        say "Removing LVM LV $VG_NAME/$LV_DATA ..."
        lvremove -f "$VG_NAME/$LV_DATA"

        say "Removing LVM VG $VG_NAME ..."
        vgremove -f "$VG_NAME"
    fi

    if [ "$ENABLE_MD" == "1" ]; then
        say "Removing LVM PV $MD_DEVICE ..."
        pvremove -f "$MD_DEVICE"

        say "Removing RAID device $MD_DEVICE ..."
        mdadm --stop "$MD_DEVICE"
        sed -i '/^# Begin of ephemeral-scripts configuration/,/^# End of ephemeral-scripts configuration/{d}' "$MD_CONFIG"

        say "Wiping RAID partitions ${partitions_list[*]} ..."
        mdadm --zero-superblock ${partitions_list[*]}
    else
        say "Removing LVM PV(s) ${partitions_list[*]} ..."
        pvremove -f ${partitions_list[*]}
    fi

    wipefs -faq ${partitions_list[*]}
    for disk in $disks_list; do
        parted --align optimal --script "$disk" rm 1
    done
    say "Wiping disks ${disks_list[*]} ..."
    wipefs -faq ${disks_list[*]}
}

ephemeral_mount() {
    if [ -b "$LV_DATA_DEV" ]; then
        if ! mountpoint -q "$MOUNT_PATH"; then
            say "Creating data mountpoint ..."
            test -d "$MOUNT_PATH" || mkdir -p "$MOUNT_PATH"
            say "Mounting data $LV_DATA_DEV to $MOUNT_PATH..."
            mount -t $MOUNT_FSTYPE -o $MOUNT_OPTIONS "$LV_DATA_DEV" "$MOUNT_PATH"
            chmod 0777 "$MOUNT_PATH"
        else
            say  "Data $LV_DATA_DEV already mounted to $MOUNT_PATH ..."
        fi
    fi

    if [ -b "$LV_SWAP_DEV" ]; then
        local swap_dev=$(readlink -f $LV_SWAP_DEV) swap
        for swap in $(swapon --noheadings --show=NAME); do
            if [ "$swap" == "$swap_dev" ]; then
                say "Swap $LV_SWAP_DEV already mounted ..."
                return
            fi
        done
        say "Mounting swap $LV_SWAP_DEV ..."
        swapon --priority 1 --discard=pages --fixpgsz "$LV_SWAP_DEV" || swapon "$LV_SWAP_DEV" || true
    fi
}

ephemeral_usage() {
    cat << EOF
    $0 [--disks <DISKS>] [--destroy] [--force]

EOF
    exit 1
}

ephemeral_main() {
    DESTROY=false
    FORCE=false
    while [ $# -gt 0 ]; do
        cmd="$1"
        shift
        case "$cmd" in
        --disks)
            DISKS="$2"
            shift
            ;;
        --destroy) DESTROY=true ;;
        --force) FORCE=true ;;
        -h | --help) ephemeral_usage ;;
        --) break ;;
        *)
            say  "ERROR: Unknown command: $cmd"
            exit 1
            ;;
        esac
    done
    if [ `id -u` != 0 ]; then
        say "ERROR: Must be root"
        exit 1
    fi

    pvscan --cache --activate ay >&2 || true
    set_defaults
    cloud_id > /dev/null
    if $DESTROY; then
        if [ -b "$LV_DATA_DEV" ] || [ -b "$LV_SWAP_DEV" ]; then
            ephemeral_destroy
        else
            say "Nothing to destroy"
        fi
        exit 0
    fi
    if $FORCE || [ ! -b "$LV_DATA_DEV" ]; then
        ephemeral_create
    fi
    ephemeral_mount
}

ephemeral_main "$@"
