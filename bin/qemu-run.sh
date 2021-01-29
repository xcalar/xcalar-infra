#!/bin/bash

set -e

SMP=${SMP:-2}
MEM=${MEM:-2048M}
FORCE=false

die() {
    echo >&2 "ERROR: $1"
    exit 1
}

usage() {
    cat <<EOF
    usage: $(basename $0) [-smp #] [-mem #M] [--serial] [--image src.qcow2]
              [--clone clone.qcow2] [-f|--force (overwrite existing clone)]
              [--size #G ] [-vnc address] -- [-qemu-arg [key1=value1,key2=value2...]]

    defaults:
        -smp $SMP
        -mem $MEM
EOF
    exit 2
}

freeport() {
    local start=$1
    local end=$((start + 20))
    local port=
    for port in $(seq $start $end); do
        if ! nc -w 1 0.0.0.0 $port >/dev/null 2>&1; then
            echo $port
            return 0
        fi
    done
    return 1
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --name)
            NAME="$1"
            shift
            ;;
        -smp | -cpu | --cpu)
            SMP="$1"
            shift
            ;;
        -m | -mem | --mem)
            MEM="$1"
            shift
            ;;
        --image)
            IMAGE="$1"
            shift
            ;;
        --clone)
            CLONE="$1"
            shift
            ;;
        -vnc | --vnc)
            VNC="$1"
            shift
            ;;
        -f | --force) FORCE=true ;;
        -h | --help) usage ;;
        --size)
            SIZE="$1"
            shift
            ;;
        --serial) ARGS+=(-serial mon:stdio) ;;
        --) break ;;
        --*) die "Unknown argument $cmd" ;;
        -*) die "Unknown argument $cmd" ;;
        *)
            if ! file "$cmd" | grep -q 'QEMU QCOW Image'; then
                die "Unrecognized file or argument: $cmd"
            fi
            IMAGE="$cmd"
            ;;
    esac
done

[ -n "$NAME" ] || die "Must specify vm name"

[ -n "$IMAGE" ] || die "No image specified. Use --image, optionally combined with --clone"

NAME_SHA="$(sha256sum <<< "$NAME" | cut -d' ' -f1)"
IMAGE_DIR=/var/tmp/$(id -u)/qemu-images
VM_DIR=/var/tmp/$(id -u)/qemu-vms/$NAME

mkdir -p $IMAGE_DIR

if [ -r "$IMAGE" ]; then
    IMAGE_TO_USE="$IMAGE"
elif [[ $IMAGE =~ ^http[s]?:// ]]; then
    IMAGE_URI_SHA="$(sha256sum <<< "$IMAGE" | cut -d' ' -f1)"
    IMAGE_BASE="$(basename "${IMAGE%\?*}")"
    IMAGE_EXT="${IMAGE_BASE##*.}"
    IMAGE_DOWNLOAD="$IMAGE_DIR/${IMAGE_URI_SHA}.${IMAGE_EXT}"
    if ! test -e "$IMAGE_DOWNLOAD"; then
        echo >&2 "NOTE: Downloading $IMAGE to $IMAGE_DOWNLOAD"
        curl -fsSL "$IMAGE" -o "$IMAGE_DOWNLOAD"
    fi
    CLONE="$VM_DIR/${NAME}.qcow2"
else
    die "Image $IMAGE not found"
fi


if [ -n "$CLONE" ]; then
    if ! [ -e "$CLONE" ] || $FORCE; then
        echo >&2 "NOTE: Creating linked clone of $IMAGE_TO_USE -> $CLONE"
        qemu-img create -f qcow2 -b "$IMAGE_TO_USE" "$CLONE" $SIZE
    else
        echo >&2 "NOTE: Using existing clone $CLONE of image ${IMAGE_TO_USE}. Use --force to recreate it"
    fi
    IMAGE_TO_USE="$CLONE"
elif ! [ -w "$IMAGE_TO_USE" ]; then
    die "$IMAGE_TO_USE is not writable. Please fix the permissions, or use --clone"
fi

if test -e "${IMAGE_TO_USE}.name"; then
    NAME=$(cat "${IMAGE_TO_USE}.name")
else
    NAME="${NAME:-$(basename $IMAGE_TO_USE .qcow2)}"
    echo $NAME >"${IMAGE_TO_USE}.name"
fi

if [ -z "$INSTANCE_ID" ]; then
    if ! [ -e "${IMAGE_TO_USE}.id" ]; then
        uuidgen | cut -d- -f1 >"${IMAGE_TO_USE}.id" || die "Failed to write out instance-id"
    fi
    INSTANCE_ID=$(cat "${IMAGE_TO_USE}.id")
fi

#    -drive file=${CI_ISO} \

set -x
exec qemu-system-x86_64 -name $NAME \
    -nodefaults \
    -enable-kvm \
    -nographic \
    -drive file=${IMAGE_TO_USE},if=virtio,cache=writeback,discard=ignore,format=qcow2 \
    -m ${MEM} \
    -smp ${SMP} \
    -machine type=pc,accel=kvm \
    -boot c ${VNC+-vnc $VNC} \
    -device virtio-net-pci,netdev=user.0 \
    -netdev user,id=user.0,hostfwd=tcp::$(freeport 2224)-:22 \
    -chardev socket,id=mon0,path=/var/tmp/monitor-$(id -u)-$NAME,nodelay,server,nowait \
    -mon chardev=mon0,id=qmon,mode=readline \
    -smbios "type=1,serial=ds=nocloud;h=${NAME}-${INSTANCE_ID}.int.xcalar.com;i=i-${INSTANCE_ID}" "${ARGS[@]}" "$@"
#-smbios "type=1,serial=ds=nocloud-net;h=${NAME}-${INSTANCE_ID}.int.xcalar.com;i=i-${INSTANCE_ID};s=http://10.10.4.6:80/" "${ARGS[@]}" "$@"
#-cdrom /root/packer/packer_cache/bbd74514a6e11bf7916adb6b0bde98a42ff22a8f853989423e5ac064f4f89395.iso
#-chardev socket,id=mon0,port=55919,host=127.0.0.1,nodelay,server,nowait
