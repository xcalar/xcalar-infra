#!/bin/bash

# This script will be executed when Jenkins job 'XcalarPersonalEditionBuilder' is triggered.
# Some env params referenced here, (such as PATH_TO_XCALAR_INSTALLER) are the
# names of params that can be specified when building the XcalarPersonalEditionBuilder job.
# Such env vars hold whichever value was provided for that param, for the build
# which triggers the script.

set -e

# the GIT repos checked out by Jenkins job; they are checked out within the job workspace
# (job workspace should be cwd when this script begins)
# see 'Source Code Management' section of job to see which subdirs each are being checked out to
CWD_START=$(pwd)
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export XLRINFRADIR="${XLRINFRADIR:-$(readlink -f $SCRIPTDIR/..)}"
export XLRGUIDIR="${XLRGUIDIR:-$CWD_START/xcalar-gui}"
export GRAFANADIR="${GRAFANADIR:-$CWD_START/graphite-grafana}"

#================================================================
# SETUP: Check out xcalar-gui project to git sha of whichever xcalar-gui was used to
# generate the RPM installer specified by PATH_TO_XCALAR_INSTALLER param.
#
# This RPM installer is what will get installed in the Docker container which
# gets packed as a Docker image in the app, and uploaded to the users machine.
# The 'xcalar-gui' which gets installed via this RPM installer, needs to be
# built with the --product=XDEE option.  However, RPM installers only build
# xcalar-gui with the standard options.
# Therefore, as part of this build, the version of xcalar-gui used in the RPM
# installer needs to be checked out, and re-built with this option, and then
# swapped with that gets installed in the Docker container.
#
# The GIT SHA for the version of xcalar-gui used, can be found in the
# build directory the RPM installer is found in, in a file called BUILD_SHA.
# Get that file, based on RPM installer path, and check out the xcalar-gui project
# to this point.
#=====================================================================

# convert RPM installer path to real path in case a symlink was specified
REAL_PATH="$(readlink -f $PATH_TO_XCALAR_INSTALLER)"
if [ ! -f "$REAL_PATH" ]; then
    echo "PATH_TO_XCALAR_INSTALLER specified, $REAL_PATH, does not exist!" >&2
    exit 1
fi
INSTALLER_DIR="$(dirname $REAL_PATH)"
SHA_FILE="$INSTALLER_DIR/../BUILD_SHA"
if [ ! -f "$SHA_FILE" ]; then
    echo "$REAL_PATH exists, but BUILD_SHA file determined for it, $SHA_FILE, does not exist!" >&2
    exit 1
fi
FRONTEND_GIT_SHA="$(grep -oP 'XD: \S+ \(\S+\)' $SHA_FILE | grep -oP '\([a-zA-Z0-9]+\)' | grep -oP '[a-zA-Z0-9]+')"
if [ -z "$FRONTEND_GIT_SHA" ]; then
    echo "XD git sha wasn't found in the GIT SHA file supplied to the RPM installer for this build. (SHA file: $SHA_FILE)" >&2
    exit 1
fi
cd "$XLRGUIDIR"
git checkout "$FRONTEND_GIT_SHA"

#=================
# Main job: Build Xcalar image, app, etc.
# (TODO: Shift this all in to one file?  File below exists already; leaving it be for now)
#================
bash -x "$XLRINFRADIR"/docker/xpe/jenkins/XcalarPersonalEditionRunner.sh
