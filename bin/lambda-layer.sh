#!/usr/bin/env bash
set -e

DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
readonly WD=${PWD}
readonly SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ARGS=("$@")
shift
PUBLISH=0
RUNTIME=python3.6
export REQ=requirements.txt

usage() {

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -h|--help) usage; exit 0;;
        --layer) LAYER_NAME="$1"; shift;;
        --publish) PUBLISH=1;;
        --runtime) RUNTIME="$1"; shift;;
        --region) export AWS_DEFAULT_REGION="$1"; shift;;
        -r|--requirements) REQ="$1"; shift;;
        --output) ZIP_ARTIFACT="$1"; shift;;
        *) echo >&2 "Unknown argument $cmd"; exit 1;;
    esac
done

if ! test -e "$REQ"; then
    echo >&2 "No requirements.txt found"
    exit 1
fi
if [ -z "$ZIP_ARTIFACT" ]; then
    ZIP_ARTIFACT=${WD}/${LAYER_NAME:-lambda}.zip
fi

if [ -z "$container" ]; then
    docker run --rm -e container=docker -v "${BASH_SOURCE[0]}"-v $WD:/var/task:z -w /var/task lambci/lambda:build-${RUNTIME} /bin/bash -x $(basename "${BASH_SOURCE[0]}") "${ARGS[@]}"

    if ((PUBLISH)); then
        echo "Publishing layer to AWS..."
        aws lambda publish-layer-version \
            --layer-name ${LAYER_NAME} \
            --zip-file fileb://${ZIP_ARTIFACT} \
            --compatible-runtimes ${RUNTIME} \
        && VERSION=$(aws lambda list-layer-versions --layer-name ${LAYER_NAME} --query 'LayerVersions[0].Version') \
        && aws lambda add-layer-version-permission \
            --statement-id xaccount-$(date +%s) \
            --action lambda:GetLayerVersion \
            --principal '*' \
            --layer-name ${LAYER_NAME} \
            --version-number ${VERSION}
    else
        echo "Wrote ${ZIP_ARTIFACT}"

    exit $?
fi

LAYER_BUILD_DIR="$(mktemp -t -d python.XXXXXX)/python"
mkdir -p $LAYER_BUILD_DIR

${RUNTIME} -m pip --isolated install -t ${LAYER_BUILD_DIR} -r "$REQ"

if ls ./*.py >/dev/null 2>&1; then
    cp -v ./*.py ${LAYER_BUILD_DIR}
fi

rm -f ${ZIP_ARTIFACT}
if [ -n "$LAYER_NAME" ]; thjen
    cd ${LAYER_BUILD_DIR}/..
    zip -9r -q ${ZIP_ARTIFACT} ./python/
else
    cd ${LAYER_BUILD_DIR}
    zip -9r -q ${ZIP_ARTIFACT} .
fi
cd - >/dev/null
chown $(stat -c %u $WD) ${ZIP_ARTIFACT}
rm -rf ${LAYER_BUILD_DIR}
exit 0
