#!/bin/bash

MOUNT_PATH="${MOUNT_PATH:-/mnt/customer-cloud-vol}"
MOUNT_TARGET="${MOUNT_TARGET:-172.16.50.244:/thirsty-awesome-skossi}"
MOUNT_OPTS="${MOUNT_OPTS:-rw,hard,nointr,rsize=32768,wsize=32768,bg,nfsvers=3,tcp}"
MOUNT_FSTYPE="${MOUNT_FSTYPE:-nfs}"
MOUNT_ARGS=
DRYRUN=${DRYRUN:-false}
FSTAB=true

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --path) MOUNT_PATH="$1"; shift;;
        --target) MOUNT_TARGET="$1"; shift;;
        --opts) MOUNT_OPTS="$1"; shift;;
        --fstype) MOUNT_FSTYPE="$1"; shift;;
        --args) MOUNT_ARGS="$1"; shift;;
        --dryrun) DRYRUN=true;;
        --no-fstab) FSTAB=false;;
        --fstab) FSTAB=true;;
        -h | --help)
            cat <<-EOF >&2
			Mounts a given target to a path
			usage: $0 [--path </path/on/local> (eg: $MOUNT_PATH)] [--target <shared-remote> (eg: $MOUNT_TARGET)] [--opts ($MOUNT_OPTS)]
			            [--fstype ($MOUNT_FSTYPE)] [--args (extra mount arguments)] [--dryrun] [--fstab (default)] [--no-fstab]
			EOF
            exit 1
            ;;
        *) echo >&2 "ERROR: Unknown argument $cmd"; exit 2;;
    esac
done

if $DRYRUN; then
    echo "$MOUNT_TARGET $MOUNT_PATH $MOUNT_FSTYPE $MOUNT_OPTS 0 0"
    exit
fi

test -d "$MOUNT_PATH" || mkdir -p "$MOUNT_PATH"

if $FSTAB; then
    sed -i '\@'"${MOUNT_PATH}"'@d' /etc/fstab
    echo "$MOUNT_TARGET $MOUNT_PATH $MOUNT_FSTYPE $MOUNT_OPTS 0 0" | tee -a /etc/fstab
    mount "$MOUNT_ARGS" "$MOUNT_PATH"
else
    if [ -d "$MOUNT_PATH" ] && mountpoint -q "$MOUNT_PATH"; then
        MOUNT_REMOUNT=",remount"
    fi
    mount -t $MOUNT_FSTYPE -o ${MOUNT_OPTS}${REMOUNT} $MOUNT_ARGS "$MOUNT_TARGET" "$MOUNT_PATH"
fi
