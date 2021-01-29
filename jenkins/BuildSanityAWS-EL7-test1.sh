#!/bin/bash

set -e
set -x

echo $GIT_ASKPASS

export XLRDIR=$PWD
export PATH=$XLRDIR/bin:$PATH
export XLRGUIDIR=$PWD/xcalar-gui
export CCACHE_DIR=$(cd .. && pwd)/ccache
export XCE_LICENSEDIR=/etc/xcalar
export ExpServerd="false"

# Set this for pytest to be able to find the correct cfg file
pgrep -u `whoami` childnode | xargs -r kill -9
pgrep -u `whoami` usrnode | xargs -r kill -9
pgrep -u `whoami` xcmgmtd | xargs -r kill -9
rm -rf /var/tmp/xcalar-`id -un`/*
mkdir -p /var/tmp/xcalar-`id -un`/sessions
sudo rm -rf /var/opt/xcalar/*
git clean -fxd -q

. doc/env/xc_aliases


pkill -9 usrnode || true
pkill -9 childnode || true
pkill -9 xcmgmtd || true

do_build () {
 xclean || true
 (echo "Constants.BufferCacheLazyMemLocking=true"; sed 's/TEMPLATE/'${HOSTNAME}'/g' src/data/template.cfg) > src/data/${HOSTNAME}.cfg

 echo "build clean"
 build clean &>/dev/null || build clean
 echo "build $1"
 build $1 CC='ccache gcc' CXX='ccache g++' &>/dev/null || build $1
 echo "build start"
 build CC='ccache gcc' CXX='ccache g++'
 echo "build end"
 echo "build sanitySerial start"
 build sanitySerial
 echo "build sanitySerial end"
}

do_build config

do_build prodconf
exit $?
