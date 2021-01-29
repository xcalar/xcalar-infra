#!/bin/bash

set +e
#docker stop $(docker ps -aq)
#docker rm $(docker ps -aq)
#docker rmi $(docker images -aq)
set -e

export XLRDIR=`pwd`
export XCE_LICENSEDIR=/etc/xcalar
export ExpServerd="false"
#export MYSQL_PASSWORD="i0turb1ne!"
export PATH="$XLRDIR/bin:$PATH"
# Set this for pytest to be able to find the correct cfg file
pgrep -u `whoami` childnode | xargs -r kill -9
pgrep -u `whoami` usrnode | xargs -r kill -9
pgrep -u `whoami` xcmgmtd | xargs -r kill -9
# Nuke as soon as possible
#ipcs -m | cut -d \  -f 2 | xargs -iid ipcrm -mid || true
#rm /tmp/xcalarSharedHeapXX* || true
rm -rf /var/tmp/xcalar-jenkins/*
mkdir -p /var/tmp/xcalar-jenkins/sessions
sudo rm -rf /var/opt/xcalar/*
git clean -fxd
git submodule init
git submodule update

. doc/env/xc_aliases


sudo pkill -9 gdbserver || true
sudo pkill -9 usrnode || true
sudo pkill -9 childnode || true
find $XLRDIR -name "core.*" -exec rm --force {} +

# Debug build
set +e
xclean
set -e
build clean
build coverage
build
#build sanity -k
build sanitySerial
bin/coverageReport.sh --output /netstore/qa/coverage --type html

# Prod build
set +e
xclean
set -e
build clean
build prod
build
#build sanity -k
build sanitySerial
