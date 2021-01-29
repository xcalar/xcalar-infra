#!/bin/bash

export XLRDIR=$PWD
export PATH=$XLRDIR/bin:$PATH
export APT_PROXY=

bash -ex bin/build-installers.sh
