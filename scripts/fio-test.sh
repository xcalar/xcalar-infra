#!/bin/bash

set -e

if test -e /etc/system-release; then
    RPM=1
    FMT=rpm
else
    RPM=0
    FMT=deb
fi

build_fio() {
    FIOVER=3.18
    FIOURL=https://github.com/axboe/fio/archive/fio-${FIOVER}.tar.gz
    DESTDIR=/tmp/fio$$
    (
        rm -rf fio*
        curl -f -L $FIOURL | tar zxf -
        cd fio*
        ./configure --prefix=/usr
        make -j$(nproc)
        make DESTDIR=$DESTDIR install
    )
    fpm -s dir -t $FMT --name fio --version $FIOVER --iteration 10 -f -C $DESTDIR
}

build_ioping() {
    IOVER=1.2
    IOPING=https://github.com/koct9i/ioping/archive/v${IOVER}.tar.gz
    DESTDIR=/tmp/ioping$$
    (
        rm -rf ioping*
        curl -L -f "$IOPING" | tar zxf -
        cd ioping*
        make PREFIX=/usr -j$(nproc)
        make DESTDIR=$DESTDIR install
        mkdir -p $DESTDIR/usr/bin
        mv $DESTDIR/usr/local/* $DESTDIR/usr/
        rm -rf ${DESTDIR:?Dont nuke my computer}/usr/local
    )
    fpm -s dir -t $FMT --name ioping --version $IOVER --iteration 10 -f -C $DESTDIR
}

deps() {
    if ((RPM)); then
        yum install -y make gcc libaio-devel
    else
        apt-get update && apt-get install -y make gcc libaio-dev
    fi
}

get_or_build() {
    if test -e /etc/system-release; then
        yum install -y $1 --enablerepo='xcalar*'
    else
        apt-get install -y $1
    fi
    if [ $? -ne 0 ]; then
        deps
        eval build_"$1"
    fi
}

checkFs() {
    fs=$(findmnt -nT ${1:-$(pwd)} | awk '{print $3}')
    case "$fs" in
        ext*|xfs) echo >&2 "Filesystem $fs is ok";;
        nfs*) echo >&2 "You must run this on local storage, not on $fs!"; exit 2;;
        *) echo >&2 "Unknown filesystem $fs, better safe than sorry. Bailing"; exit 2;;
    esac
}


if [ $(id -u) != 0 ]; then
    echo >&2 "Need to run as root"
    exit 1
fi

checkFs "$(pwd)"

export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin

set +e
for req in fio ioping; do
    if ! command -v $req; then
        get_or_build $req
    fi
done

set -e

ioping -c 10 .

fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=4G --readwrite=randrw --rwmixread=75
fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=4G --readwrite=randread
fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=4G --readwrite=randwrite
