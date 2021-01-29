#!/bin/bash
#
# shellcheck disable=SC1091,SC2086

set -e

export XLRINFRADIR=${XLRINFRADIR:-$PWD}
export PATH=$XLRINFRADIR/bin:/opt/xcalar/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin:$HOME/.local/bin:$HOME/bin
export OUTDIR=${OUTDIR:-$PWD/output}
export MANIFEST=$OUTDIR/packer-manifest.json
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}
export PROJECT=${PROJECT:-xdp-awsmp}

export PUPPET_SRC=$PWD/puppet
export PUPPET_SHA1=$(cd $PUPPET_SRC && git rev-parse --short HEAD)
export OUTPUT_DIRECTORY=/netstore/builds/byJob/${JOB_NAME}/${BUILD_NUMBER}
export PACKER_NO_COLOR=1
export CHECKPOINT_DISABLE=1

mkdir -p $OUTPUT_DIRECTORY

. infra-sh-lib
. aws-sh-lib

if [ -z "$VAULT_TOKEN" ]; then
    export VAULT_TOKEN=$($XLRINFRADIR/bin/vault-auth-puppet-cert.sh --print-token)
fi

if [ -n "$JENKINS_URL" ]; then
    if test -e .venv/bin/python2; then
        REBUILD_VENV=true
    fi
fi
if [ -n "$REBUILD_VENV" ]; then
    rm -rf .venv
fi

if ! make venv; then
    make clean
    make venv
fi

source .venv/bin/activate || die "Failed to activate venv"

test -d "$OUTDIR" || mkdir -p "$OUTDIR"
if ! test -e $MANIFEST; then
    curl -fsSL ${JOB_URL}/lastSuccessfulBuild/artifact/output/packer-manifest.json -o $MANIFEST || true
fi

cd packer/qemu

cp $MANIFEST . || true

export TARGET_OSID=${TARGET_OSID:-el7}
export ROLE=${ROLE:-jenkins_slave}
export CLUSTER=${CLUSTER:-jenkins-slave}
export TARGET=${TARGET_OSID}-${ROLE}-${CLUSTER}-qemu

set +e
make ${TARGET}/tdhtest BUILD_NUMBER=$BUILD_NUMBER OUTPUT_DIRECTORY=$OUTPUT_DIRECTORY OUTDIR=$OUTDIR PUPPET_SRC=$PUPPET_SRC PUPPET_SHA1=$PUPPET_SHA1 VM_NAME="${TARGET}-${BUILD_NUMBER}" MANIFEST=$MANIFEST ROLE=$ROLE CLUSTER=$CLUSTER TARGET_OSID=$TARGET_OSID
rc=$?
if [ $rc -eq 0 ]; then
    if test -e $(basename $MANIFEST); then
        cp $(basename $MANIFEST) $MANIFEST
    fi
fi
pkill -ef qemu-
exit $rc
