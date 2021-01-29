#!/bin/bash

touch /tmp/${JOB_NAME}_${BUILD_ID}_START_TIME

export XLRDIR=`pwd`
export ExpServerd="false"
export PATH="/opt/clang/bin:$XLRDIR/bin:$PATH"
export CCACHE_BASEDIR=$XLRDIR

. $XLRDIR/bin/jenkins/jenkinsUtils.sh
source $XLRDIR/doc/env/xc_aliases

trap "genBuildArtifacts" EXIT

xcEnvEnter "$HOME/.local/lib/$JOB_NAME"

rpm -q xcalar && sudo yum remove -y xcalar
sudo rm -rf /opt/xcalar/scripts

pkill -9 gdbserver || true
pkill -9 usrnode || true
pkill -9 childnode || true
pkill -9 xcmgmtd || true
pkill -9 xcmonitor || true

rm -rf /var/tmp/xcalar-`id -un`/* /var/tmp/xcalar-`id -un`/*
mkdir -p /var/tmp/xcalar-`id -un`/sessions /var/tmp/xcalar-`id -un`/sessions
sudo ln -sfn $XLRDIR/src/data/qa /var/tmp/
sudo ln -sfn $XLRDIR/src/data/qa /var/tmp/`id -un`-qa

git clean -fxd >/dev/null

find $XLRDIR -name "core.*" -exec rm --force {} +

set +e
xclean
set -e

ccache -s

# debug build
build clean  >/dev/null
build config  >/dev/null
build CC="ccache gcc" CXX="ccache g++"
ccache -s
build sanitySerial

set +e
xclean
set -e

# prod build
build clean >/dev/null
build prod CC="ccache gcc" CXX="ccache g++"
build sanitySerial
ccache -s
