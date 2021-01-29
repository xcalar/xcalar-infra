#!/bin/bash

export PS4='# ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]}() - [${SHLVL},${BASH_SUBSHELL},$?] '
set -x
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin

XCE_CONFDIR="${XCE_CONFDIR:-/etc/xcalar}"
OSID=${OSID:-$(osid)}

yum localinstall -y http://repo.xcalar.net/rpm-deps/common/x86_64/Packages/ephemeral-disk-1.0-42.noarch.rpm || true
EPHEMERAL=${EPHEMERAL:-/ephemeral/data}
systemctl daemon-reload
systemctl disable ephemeral-disk
NOW=$(date +%s)
if test -x /usr/bin/ephemeral-disk; then
    /usr/bin/ephemeral-disk || true
    until mountpoint -q $EPHEMERAL; do
        echo >&2 "Waiting for $EPHEMERAL mount point to show up ..."
        sleep 5
        if [[ $(( $(date +%s) - NOW )) -gt 120 ]]; then
            echo >&2 "Giving up on $EPHEMERAL"
            break
        fi
    done
fi

if [ -z "$TMPDIR" ]; then
    if [ -w "$EPHEMERAL" ]; then
        export TMPDIR=$EPHEMERAL/tmp
    elif [ -e /mnt/resource ]; then
        export TMPDIR=/mnt/resource/tmp
    elif mountpoint -q /mnt; then
        export TMPDIR=/mnt/tmp-installer-$(id -u)
    else
        export TMPDIR=/tmp/installer-$(id -u)
    fi
fi
test -d "$TMPDIR" || mkdir -p -m 1777 -p $TMPDIR
export TMPDIR=$TMPDIR/installer-$(id -u)
mkdir -p "$TMPDIR"
trap "cd / && rm -rf $TMPDIR" EXIT

download_file() {
    if [[ $1 =~ ^s3:// ]]; then
        aws s3 cp $1 $2
    else
        curl -f -L "${1}" -o "${2}"
    fi
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2 "!!! FAILED TO DOWNLOAD $1 !!!"
        echo >&2 "!!! $1 -> $2"
        echo >&2 "!!! rc=$rc"
    fi
    return $rc
}

aws_s3_from_url() {
    local clean_url="${1%%\?*}"
    clean_url="${clean_url#https://}"
    if [[ $clean_url =~ ^s3 ]]; then
        echo "s3://${clean_url#*/}"
        return 0
    fi
    local host="${clean_url%%/*}"
    local bucket="${host%%.*}"
    local s3host="${host#$bucket.}"
    if ! [[ $s3host =~ ^s3 ]]; then
        return 1
    fi
    local key="${clean_url#$host/}"
    echo "s3://${bucket}/${key}"
}

set +e
set -x
if [ -n "$INSTALLER_URL" ]; then
    set +e
    set -x
    INSTALLER_FILE=$TMPDIR/xcalar-installer.sh
    if [[ $INSTALLER_URL =~ ^s3:// ]]; then
        if ! aws s3 cp "$INSTALLER_URL" "$INSTALLER_FILE"; then
            rm -f "$INSTALLER_FILE"
        fi
    elif INSTALLER_S3=$(aws_s3_from_url "$INSTALLER_URL") && [ -n "$INSTALLER_S3" ]; then
        if ! aws s3 cp "$INSTALLER_S3" "$INSTALLER_FILE"; then
            rm -f "$INSTALLER_FILE"
        fi
    fi
    test -f "$INSTALLER_FILE" || download_file "$INSTALLER_URL" "$INSTALLER_FILE"
    rc=$?
    if [ $rc -eq 0 ]; then
        bash -x "$INSTALLER_FILE" --nostart
        rc=$?
    fi
    if [ $rc -ne 0 ]; then
        echo >&2 "!!! FAILED TO RUN INSTALLER !!!"
        echo >&2 "!!! $INSTALLER_URL -> $INSTALLER_FILE"
        echo >&2 "!!! rc=$rc"
        env >&2
        exit $rc
    fi
    rm -v -f "${INSTALLER_FILE}"
fi

echo >&2 "Setting up cgroups"
/opt/xcalar/bin/cgconfig-setup.sh

#echo '/mnt/xcalar/pysite' > /opt/xcalar/lib/python3.6/site-packages/mnt-xcalar-pysite.pth
#mkdir -p /var/opt/xcalar/pysite
#chown xcalar:xcalar /var/opt/xcalar/pysite

LICENSE_FILE="${XCE_CONFDIR}/XcalarLic.key"
if [ -z "$LICENSE" ] && [ -n "$LICENSE_URL" ]; then
    set +e
    case "$LICENSE_URL" in
        https://*)
            LICENSE="$(curl -fsSL "$LICENSE_URL")"
            ;;
        s3://*)
            LICENSE="$(aws s3 cp "$LICENSE_URL" -)"
            ;;
        *)
            LICENSE="$(cat "${LICENSE_URL#file://}")"
            ;;
    esac
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$LICENSE" ]; then
        echo >&2 "!!! FAILED TO DOWNLOAD LICENSE !!!"
        echo >&2 "!!! $LICENSE_URL -> $LICENSE_FILE"
        echo >&2 "!!! rc=$rc"
        env >&2
        exit $rc
    fi
fi
touch "$LICENSE_FILE"
if [ -n "$LICENSE" ]; then
    (set -o pipefail; echo "$LICENSE" | base64 -d | gzip -dc) > "$LICENSE_FILE".tmp \
        && mv "$LICENSE_FILE".tmp "$LICENSE_FILE"
fi
chmod 0600 "$LICENSE_FILE"
chown xcalar:xcalar "$LICENSE_FILE"

set +e
set -x
if [ -n "$POSTINSTALL_URL" ]; then
    POSTINSTALL=$TMPDIR/post.sh
    download_file "${POSTINSTALL_URL}" "${POSTINSTALL}"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2 "!!! FAILED TO DOWNLOAD POSTINSTALL SCRIPT!!!"
        echo >&2 "!!! $POSTINSTALL_URL -> $POSTINSTALL"
        echo >&2 "!!! rc=$rc"
        env >&2
        exit $rc
    fi
fi
if [ -n "${POSTINSTALL}" ]; then
    bash -x "${POSTINSTALL}" "$@"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2 "!!! FAILED TO RUN POSTINSTALL SCRIPT!!!"
        echo >&2 "!!! $POSTINSTALL $*"
        echo >&2 "!!! rc=$rc"
        env >&2
        exit $rc
    fi
fi


yum clean all --enablerepo='*'
rm -rf /var/tmp/yum* /var/cache/yum/*

#sed -i '/# Provides:/a# Should-Start: cloud-final' /etc/init.d/xcalar

exit 0
