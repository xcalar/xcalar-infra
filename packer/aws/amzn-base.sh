#!/bin/bash
#
# shellcheck disable=SC1091,SC2086

. infra-sh-lib
. aws-sh-lib

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE=$DIR/amzn-base.yaml
MANIFEST="$(basename "$TEMPLATE" .yaml)"-manifest.json
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -t|--template) TEMPLATE="$1"; shift;;
        --installer) INSTALLER="$1"; shift;;
        --project) PROJECT="$1"; shift;;
        --product) PRODUCT="$1"; shift;;
        *) die "Unknown parameter $cmd";;
    esac
done

export PROJECT=${PROJECT:-xcalar}
export PRODUCT=${PRODUCT:-base-ami}
chmod 0700 $XLRINFRADIR/packer/ssh
chmod 0600 $XLRINFRADIR/packer/ssh/id_packer.pem

if ! jq -r . < $TEMPLATE >/dev/null 2>&1; then
    if ! cfn-flip < ${TEMPLATE} > ${TEMPLATE%.*}.json; then
        die "Failed to convert template $TEMPLATE"
    fi
    TEMPLATE="${TEMPLATE%.*}.json"
fi

if ! installer-version.sh "$INSTALLER" > installer-version.json; then
    die "Failed to get installer info"
fi
if [ -z "$INSTALLER_URL" ]; then
    if  ! INSTALLER_URL="$(installer-url.sh -d s3 "$INSTALLER")"; then
        die "Failed to get installer url for $INSTALLER"
    fi
fi

INSTALLER_URL="${INSTALLER_URL%\?*}"

# eval $(vault-aws-credentials-provider.sh -e)

if ! packer.io build \
    -machine-readable \
    -timestamp-ui \
    -only=amazon-ebs-amzn2 \
    -var base_owner='137112412989' \
    -var region=${AWS_DEFAULT_REGION:-us-west-2} \
    -var destination_regions=${REGIONS:-us-west-2} \
    -var disk_size=${DISK_SIZE:-10} \
    -var manifest="$MANIFEST" \
    -var installer="$INSTALLER" \
    -var installer_url="$INSTALLER_URL" \
    -var-file installer-version.json \
    -var project='xcalar' \
    -var product='base-image' \
    -parallel-builds=1 $TEMPLATE; then
    exit 1
fi

if ami_amzn2=$(packer_ami_from_manifest amazon-ebs-amzn2 $MANIFEST); then
    #echo "ami_amzn1: $ami_amzn1"
    echo "ami_amzn2: $ami_amzn2"
    exit 0
fi
exit 1
