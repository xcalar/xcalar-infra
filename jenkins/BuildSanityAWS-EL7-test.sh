#!/bin/bash

set -e
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


pkill -9 python || true
pkill -9 usrnode || true
pkill -9 childnode || true
pkill -9 xcmgmtd || true

do_build () {
 xclean || true
 (echo "Constants.BufferCacheLazyMemLocking=true"; sed 's/TEMPLATE/'${HOSTNAME}'/g' src/data/template.cfg) > src/data/${HOSTNAME}.cfg

 build clean
 build $1 CC='ccache gcc' CXX='ccache g++'
 build CC='ccache gcc' CXX='ccache g++'
 build sanitySerial
}

do_build coverage
bin/coverageReport.sh --output /netstore/qa/coverage --type html

do_build prod
exit $?


#bash -ex bin/build-installers.sh
git clean -fxd
(echo "Constants.BufferCacheLazyMemLocking=true"; sed 's/TEMPLATE/'${HOSTNAME}'/g' src/data/template.cfg) > src/data/${HOSTNAME}.cfg
. doc/env/xc_aliases
xclean
build clean
build config
build CC='ccache gcc' CXX='ccache g++'


build sanitySerial
