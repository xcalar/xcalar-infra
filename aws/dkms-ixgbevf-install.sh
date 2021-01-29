#!/bin/bash
MOD=ixgbevf
VER=2.16.4
if [ $UID -ne 0 ]; then
    exec sudo -n "$0" "$@"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2 "ERROR($rc): Failed to run with sudo. Must run this script as root."
        exit $rc
    fi
    exit 0
fi

set -x
set +e
if [ "$(modinfo $MOD | awk '/^version:/{print $2}')" != "$VER" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get upgrade -y
    apt-get install -y dkms linux-headers-`uname -r`

    cd /usr/src
    #wget "sourceforge.net/projects/e1000/files/ixgbevf stable/$VER/ixgbevf-$VER.tar.gz"
    curl -sSL http://repo.xcalar.net/drivers/$MOD-$VER.tar.gz | tar zxf -
    cat > /usr/src/$MOD-$VER/dkms.conf<<EOF
PACKAGE_NAME="$MOD"
PACKAGE_VERSION="$VER"
CLEAN="cd src/; make clean"
MAKE="cd src/; make BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_LOCATION[0]="src/"
BUILT_MODULE_NAME[0]="$MOD"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="$MOD"
AUTOINSTALL="yes"
EOF
    dkms add -m $MOD -v $VER && \
    dkms build -m $MOD -v $VER && \
    dkms install -m $MOD -v $VER && \
    update-initramfs -c -k all || \
    exit 0
fi

ETHDEV="$(ip route get 8.8.8.8 | awk '{ print $(NF-2); exit }')"
if [ -n "$ETHDEV" ]; then
    ETHVER="$(ethtool -i $ETHDEV | awk '/^version: /{print $2}')"
    if [ -n "$ETHVER" ] && [ "$ETHVER" != "$VER" ]; then
        rmmod "$MOD"
        modprobe -a "$MOD"
        res=$?
        if [ $res -ne 0 ]; then
            echo >&2 "ERROR($res): Couldn't modprobe $MOD. Ignoring."
        fi
    fi
fi
exit 0
