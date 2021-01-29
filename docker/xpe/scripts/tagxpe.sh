# XPE builds will need certain tags to be exported in the app
# here are some utilities for setting up those tags and removing them as bld cleanups

set -e

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASH_FUNCS="$SCRIPTDIR/local_installer_mac.sh"

: "${BUILD_NUMBER:?Need to set non-empty env var BUILD_NUMBER}"
: "${XCALAR_IMAGE_NAME:?Need to set Docker image to base tag(s) on as XCALAR_IMAGE_NAME}"
: "${BUILD_NUMBER:?Need to set build number as BUILD_NUMBER}"
: "${OFFICIAL_RELEASE:?Need true/false env var OFFICIAL_RELEASE}"

buildTag="$BUILD_NUMBER"
if [ "$OFFICIAL_RELEASE" = true ]; then
    : "${XCALAR_CONTAINER_NAME:?Need Docker container name to obtain build info from, as XCALAR_CONTAINER_NAME}"
    buildTag=$(docker exec $XCALAR_CONTAINER_NAME rpm -q xcalar --qf '%{VERSION}-%{RELEASE}')
fi
TAGGED_IMAGES_LIST=("$XCALAR_IMAGE_NAME:current" "$XCALAR_IMAGE_NAME:lastInstall" "$XCALAR_IMAGE_NAME:$buildTag")

# Start with some base image (<img name>:<tag> or img id)
# and create all the tags needed then tar those tags
cmd_create_xpe_tar() {
    if [ -z "$1" ]; then
        echo "First arg should be input image to base tags on" >&2
        exit 1
    fi
    if [ -z "$2" ]; then
        echo "2nd arg: Need to supply name of output tar file" >&2
        exit 1
    fi
    baseImage="$1"
    tarfile="$2"
    taggedImageList=""
    for taggedImageName in ${TAGGED_IMAGES_LIST[@]}; do
        docker tag "$baseImage" "$taggedImageName"
        taggedImageList="$taggedImageList $taggedImageName"
    done
    docker save $taggedImageList | gzip > "$tarfile" # if you quote "$taggedImageList", docker cmd will fail if more than one item in the String
}

# removes image tags specific for the XPE build (and containers associated w them)
# Intended to be called (by Jenkins slave) after building via XcalarPersonalEditionBuilder.js
# If use this as cleanup, this will remove the build specific image tags
# but <image>:latest remains in cache so future builds on same machine will run quicker
cmd_cleanup() {
    for taggedImageName in ${TAGGED_IMAGES_LIST[@]}; do
        "$BASH_FUNCS" cleanly_delete_docker_image "$taggedImageName"
    done
}

command="$1"
shift
cmd_${command} "$@"
