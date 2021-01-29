#!/bin/bash
#
# shellcheck disable=SC2086,SC1091

. infra-sh-lib

DESTDIR=/srv/reposync/mirror
REPOID=updates

usage() {
    cat <<EOF
    usage: $0 [-p|--download_path DESTDIR (def: $DESTDIR)] [-r|--repoid REPOID (def: $REPOID)]

    Downloads a repository for mirroring
EOF
}

main() {
    while [ $# -gt 0 ]; do
        cmd="$1"
        shift
        case "$cmd" in
            -p|--download-path) DESTDIR="$1"; shift;;
            -r|--repoid) REPOID="$1"; shift;;
            --releasever) RELEASEVER="$1"; shift;;
            -h|--help) usage; exit 0;;
            *)
                :
                ;;
        esac
    done
    if [ -z "${RELEASEVER:-}" ]; then
        if RELEASEVER=$(rpm -qf /etc/system-release --qf '%{VERSION}\n'); then
            RELEASEVER="${RELEASEVER:0:1}"
        fi
    fi
    local repoid
    RELDIR=$DESTDIR/$RELEASEVER
    for repoid in ${REPOID//,/ }; do
        FINAL=$DESTDIR/$RELEASEVER/$repoid
        if ! test -d $FINAL; then mkdir $FINAL || die "Failed to create $FINAL"; fi
        if ! test -e $RELDIR/yum.conf; then
           yumconf > $RELDIR/yum.conf
        fi
        reposync -c $RELDIR/yum.conf --delete --repoid=$repoid --newest-only --download_path=$RELDIR/
        createrepo --pretty --update --retain-old-md=2 $DESTDIR/$RELEASEVER/$repoid/
    done
}

sync() {
    :
}

yumconf() {
    cat <<EOF
[main]
cachedir=/var/cache/yum/$RELEASEVER
keepcache=0
debuglevel=2
logfile=/var/log/yum.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=2
distroverpkg=centos-release
override_install_langs=en_US.utf8
tsflags=nodocs
metadata_expire=30m
exclude=kernel kernel-debug* kernel-devel* kernel-tools* linux-firmware microcode_ctl *.i?86 *.i686 firefox* java-1.7.* java-1.11.* evolution* thunderbird iwl* j*-11.*
EOF
}

main "$@"
