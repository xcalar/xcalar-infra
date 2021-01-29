#!/bin/bash

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

wait_mount () {
    until mountpoint -q "$1"; do
        echo "$(date) Waiting for $1"
        sleep 5
    done
}

XCE_XDBSERDES="$(awk -F'=' '/^Constants.XdbLocalSerDesPath/{print $2}' /etc/xcalar/default.cfg)"
XCE_HOME="$(awk -F'=' '/^Constants.XcalarRootCompletePath/{print $2}' /etc/xcalar/default.cfg)"

if [ -n "$XCE_XDBSERDES" ]; then
    XCE_XDBSERDES_MOUNT="$(dirname $XCE_XDBSERDES)"
    wait_mount "$XCE_XDBSERDES_MOUNT"
    mkdir -p $XCE_XDBSERDES
    chown xcalar:xcalar $XCE_XDBSERDES
fi

if [ -n "$XCE_HOME" ] && [[ "$XCE_HOME" =~ ^/mnt ]]; then
    wait_mount "$XCE_HOME"
fi
