#!/bin/bash

export XLRDIR=$PWD
export PATH=$XLRDIR/bin:$PATH
export XLRGUIDIR=$PWD/xcalar-gui

export CCACHE_DIR=$(cd .. && pwd)/ccache
export CCACHE_BASEDIR=$XLRDIR

git clean -fxd -q
(echo "Constants.BufferCacheLazyMemLocking=true"; sed 's/TEMPLATE/'${HOSTNAME}'/g' src/data/template.cfg) > src/data/${HOSTNAME}.cfg
. doc/env/xc_aliases
xclean
build clean &>/dev/null
build config  &>/dev/null
build CC='ccache gcc' CXX='ccache g++'


build sanitySerial
