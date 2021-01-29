#!/bin/bash
set -e

if [ -n "$1" ]; then
    BLD_TYPE="$1"
    shift
fi
export BLD_TYPE=${BLD_TYPE:-debug}

cd ${XLRDIR?Need XLRDIR set}
PY=$(command -v python3)
if [[ ${PY#${XLRDIR}/} =~ ^/ ]]; then
    source bin/xcsetenv
    hash -r
    PY=$(command -v python3)
fi

CLANG=${CLANG:-/opt/clang5}
test -e $CLANG && export PATH=$CLANG/bin:$PATH || true

export ASAN_OPTIONS=suppressions=$XLRDIR/bin/ASan.supp
export LSAN_OPTIONS=suppressions=$XLRDIR/bin/LSan.supp

export CCC_CC=clang
export CCC_CXX=clang++

PREFIX=/opt/xcalar

scan_build() {
    scan-build -o $XLRDIR/clangScanBuildReports -v --force-analyze-debug-code -disable-checker deadcode.DeadStores --keep-going "$@"
}

cmake_config() {
    BUILD_ARGS=""
    if [ "$1" = "debug" ]; then
        BUILD_TYPE="Debug"
        BUILD_ARGS="$BUILD_ARGS -DENABLE_ASSERTIONS=ON"
    elif [ "$1" = "prod" ]; then
        BUILD_TYPE="RelWithDebInfo"
    elif [ "$1" = "release" ]; then
        BUILD_TYPE="Release"
    elif [ "$1" = "qa" ]; then
        BUILD_TYPE="RelWithDebInfo"
        BUILD_ARGS="$BUILD_ARGS -DENABLE_ASSERTIONS=ON"
    else
        echo "Build type '$1' not recognized" >&2
        exit 1
    fi

    BUILD_ARGS="$BUILD_ARGS -DXCALAR_BUILD_TYPE:STRING=$1"
    shift

    if [ "$BUFCACHEPOISON" = "true" ]; then
        BUILD_ARGS="$BUILD_ARGS -DBUFCACHEPOISON=ON"
    fi

    if [ "$BUFCACHETRACE" = "true" ]; then
        BUILD_ARGS="$BUILD_ARGS -DBUFCACHETRACE=ON"
    fi

    if [ "$CUSTOM_HEAP" = "true" ]; then
        BUILD_ARGS="$BUILD_ARGS -DCUSTOM_HEAP=ON"
    fi

    if [ "$BUFCACHESHADOW" = "true" ]; then
        BUILD_ARGS="$BUILD_ARGS -DBUFCACHESHADOW=ON"
    fi
    echo "-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DCMAKE_PREFIX_PATH:PATH=$PREFIX -DCMAKE_INSTALL_PREFIX:PATH=$PREFIX $BUILD_ARGS"
}

export BUILD_DIR=$XLRDIR/buildOut
rm -rf "${BUILD_DIR:?}"/*
mkdir -p $BUILD_DIR
cd $BUILD_DIR
scan_build cmake -GNinja -DUSE_CCACHE=OFF -DCMAKE_CXX_COMPILER=$CCC_CXX -DCMAKE_C_COMPILER=$CCC_CC $(cmake_config $BLD_TYPE) ..
scan_build "$@" ninja
