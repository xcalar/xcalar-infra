#!/bin/bash
#
# shellcheck disable=SC1091,SC2086

set -e

export XLRINFRADIR=${XLRINFRADIR:-$PWD}
export PATH=$XLRINFRADIR/bin:/opt/xcalar/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin:$HOME/.local/bin:$HOME/bin
export OUTDIR=${OUTDIR:-$PWD/output}
MANIFEST=$OUTDIR/packer-manifest.json
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}
export PROJECT=${PROJECT:-xdp-awsmp}

export PACKER_NO_COLOR=1
export CHECKPOINT_DISABLE=1

if [ -n "$EXECUTOR_NUMBER" ]; then
    git clean -fxd aws packer azure
fi

. infra-sh-lib
. aws-sh-lib

export VAULT_TOKEN=$($XLRINFRADIR/bin/vault-auth-puppet-cert.sh --print-token)

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

resolve_installer() {
    if [ -z "$INSTALLER_URL" ]; then
        if [ -d "$INSTALLER" ]; then
            echo "INSTALLER=$INSTALLER is a directory. Looking for an installer."
            INSTALLER=$(find $INSTALLER/ -type f -name 'xcalar-*-installer' | grep prod | head -1)
        fi

        if ! [ -r "$INSTALLER" ]; then
            die "Unable to find installer INSTALLER=$INSTALLER"
        fi
        CLOUD_STORE=${CLOUD_STORE:-s3}
        if ! INSTALLER_URL="$(installer-url.sh -d $CLOUD_STORE $INSTALLER)"; then
            die "Failed to upload $INSTALLER to $CLOUD_STORE"
        fi
    fi
    set -a
    if [ -n "$INSTALLER" ]; then
        eval "$(installer-version.sh --format=sh --image_build_number=$BUILD_NUMBER "$INSTALLER")"
    elif [ -n "$INSTALLER_URL" ]; then
        eval "$(installer-version.sh --format=sh --image_build_number=$BUILD_NUMBER "${INSTALLER_URL%%\?*}")"
    fi
    set +a
}

do_packer() {
    case "$BUILDER" in
        amazon-*)
            CLOUD=aws
            CLOUD_STORE=s3
            ;;
        arm-* | azure-*)
            CLOUD=azure
            CLOUD_STORE=az
            ;;
        google*)
            CLOUD=google
            CLOUD_STORE=gs
            ;;
        qemu*)
            CLOUD=qemu
            CLOUD_STORE=
            ;;
    esac

    resolve_installer

    if [ -z "$LICENSE" ]; then
        if [ -z "$LICENSE_FILE" ]; then
            if build_is_rc "$INSTALLER"; then
                LICENSE_FILE="$XLRINFRADIR/aws/cfn/${PROJECT}/license-rc.txt"
            else
                LICENSE_FILE="$XLRINFRADIR/aws/cfn/${PROJECT}/license.txt"
            fi
        fi
        if test -e "$LICENSE_FILE"; then
            LICENSE="$(cat $LICENSE_FILE)"
        else
            say "License file $LICENSE_FILE not found"
        fi
    fi

    cd $XLRINFRADIR/packer/aws
    #export INSTALLER_URL=$(installer-url.sh -d s3 $INSTALLER)
    #cfn-flip < $PACKERCONFIG > packer.json

    unset INSTALLER
    export INSTALLER_URL
    if ! test -e $(basename $MANIFEST); then
        cp -a $MANIFEST . || true
    fi
    bash -x ../build.sh --template $PACKERCONFIG --installer-url "$INSTALLER_URL" -- ${BUILDER:+-only=${BUILDER}} ${PRODUCT:+-var product=$PRODUCT }-var project=${PROJECT} -var bootstrap="$XLRINFRADIR/aws/cfn/$PROJECT/scripts/user-data.sh" -var license="${LICENSE}" -var disk_size=$DISK_SIZE 2>&1 | tee $OUTDIR/output.txt
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        exit 1
    fi
    cp packer-manifest.json $MANIFEST

    rm -f $OUTDIR/amis.yaml
    local builder
    for builder in ${BUILDER//,/ }; do
        grep -A5 "${builder}: AMIs were created:" $OUTDIR/output.txt | grep "ami-" | tee -a $OUTDIR/amis.yaml
    done
}

#get_ami_from_manifest() {
#    local builder="$1"
#    local package=${2:-packer-manifest.json}
#    local region="${3:-$AWS_DEFAULT_REGION}"
#    local uuid="$4"
#    if [ -z "$uuid" ]; then
#        if ! uuid=$(jq -r ".last_run_uuid" < $package); then
#            return 1
#        fi
#    fi
#    local ami_id
#    if ! ami_id=$(jq -r '.builds[]|select(.name == "'$builder'")|select(.packer_run_uuid == "'$uuid'") .artifact_id' < $package | grep $region); then
#        return 1
#    fi
#    echo "${ami_id#$region:}"
#}

do_upload_template() {
    (
        cd $XLRINFRADIR/aws/cfn
        local builder osid
        packer_manifest_all $MANIFEST >$OUTDIR/amis.yaml
        if [ -z "$INSTALLER_TAG" ]; then
            set -a
            eval $(installer-version.sh --format=sh "$INSTALLER")
            set +a
        fi
        for builder in ${BUILDER//,/ }; do
            osid="${builder##*-}"
            dc2 upload --project ${PROJECT} --manifest $MANIFEST \
                $(installer-version.sh --format=clieq "$INSTALLER") \
                ${RELEASE:+--release ${RELEASE}} \
                --url-file $OUTDIR/template-${builder}.url
        done
    )
}

if [ "${DO_PACKER:-true}" == true ]; then
    do_packer
else
    if ! test -e $MANIFEST; then
        curl -fsSL ${JOB_URL}/lastSuccessfulBuild/artifact/output/packer-manifest.json -o $MANIFEST
    fi
fi
do_upload_template
