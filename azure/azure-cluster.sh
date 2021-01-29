#!/bin/bash
#
# Deploy a Xcalar cluster on Azure

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

export PATH=$XLRINFRADIR/bin:$PATH

source infra-sh-lib
source azure-sh-lib

#INSTALLER="${INSTALLER:-/netstore/qa/Downloads/byJob/BuildTrunk/xcalar-latest-installer-prod}"
COUNT=1
INSTANCE_TYPE=''
CLUSTER="$(id -un)-xcalar"
LOCATION="westus2"
TEMPLATE="$XLRINFRADIR/azure/xdp-standard/devTemplate.json"

BUCKET="${BUCKET:-xcrepo}"
CUSTOM_SCRIPT_NAME="devBootstrap.sh"

BOOTSTRAP="${BOOTSTRAP:-$XLRINFRADIR/azure/bootstrap/$CUSTOM_SCRIPT_NAME}"
BOOTSTRAP_SHA=$(sha1sum "$BOOTSTRAP" | awk '{print $1}')
S3_BOOTSTRAP_KEY="bysha1/$BOOTSTRAP_SHA/$(basename $BOOTSTRAP)"
S3_BOOTSTRAP="s3://$BUCKET/$S3_BOOTSTRAP_KEY"
PARAMETERS_DEFAULTS="${PARAMETERS_DEFAULTS:-$XLRINFRADIR/azure/xdp-standard/defaults.json}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://s3-us-west-2.amazonaws.com/$BUCKET/$S3_BOOTSTRAP_KEY}"
#IMAGEID="xdp-sol11-gssim1-rg/xcalar-base-el7-01"
# Netstore in xcalardev-net vNET. Avoid having to query DNS for this on boot.
#SHARE_NAME="10.11.1.5:/data/nfs"

image_id() {
    local rg="${1%/*}"
    local img="${1#*/}"
    local subid
    if ! subid="$(az_subscription)"; then
        die "Failed to get subscription"
    fi
    echo "/subscriptions/${subid}/resourceGroups/${rg}/providers/Microsoft.Compute/images/${img}"
}

usage() {
    cat <<EOF
    usage: $0 -i installer -t instance-type [-c count (default: $COUNT)] [-n clusterName (default: $CLUSTER)]
            [-l location (default: $LOCATION)] [-k licenseKey] [-s server:/share] [-x template.json (default: $TEMPLATE)]
            [-m imageid]

EOF
}

while getopts "hi:c:t:n:l:k:s:p:x:m:" opt "$@"; do
    case "$opt" in
        h)
            usage
            exit 0
            ;;
        i) INSTALLER="$OPTARG" ;;
        c) COUNT="$OPTARG" ;;
        t) INSTANCE_TYPE="$OPTARG" ;;
        n) CLUSTER="$OPTARG" ;;
        l) LOCATION="$OPTARG" ;;
        k) LICENSE="$OPTARG" ;;
        s) SHARE_NAME="$OPTARG" ;;
        p) PARAMETERS_DEFAULTS=$OPTARG ;;
        x) TEMPLATE="$OPTARG" ;;
        m) IMAGEID="$OPTARG" ;;
        \?)
            echo >&2 "Invalid option. $OPTARG"
            usage >&2
            exit 1
            ;;
        :)
            echo >&2 "Invalid option. $OPTARG requires argument."
            usage >&2
            exit 1
            ;;
    esac
done

# Check if S3_BOOTSTRAP exists
http_code=
if ! http_code="$(curl -f -o /dev/null -s -L -w '%{http_code}\n' -I "${BOOTSTRAP_URL}")" || [ "$http_code" != 200 ]; then
    echo "$S3_BOOTSTRAP does not exists. Uploading $BOOTSTRAP"
    aws s3 cp --acl public-read "$BOOTSTRAP" "$S3_BOOTSTRAP"
fi

az group create --name "$CLUSTER" --location "$LOCATION" --tags adminEmail=${BUILD_USER_EMAIL:-$(git config user.email)} owner="${BUILD_USER_ID:-$(git config user.name)}" deployHost="$(hostname -s)"

if [ -n "$INSTALLER" ] && [ -z "$INSTALLER_URL" ]; then
    if [ "$INSTALLER" = "none" ]; then
        INSTALLER_URL="http://none"
    elif [[ $INSTALLER =~ ^s3:// ]]; then
        if ! INSTALLER_URL="$(aws s3 presign "$INSTALLER")"; then
            echo >&2 "Unable to sign the s3 uri: $INSTALLER"
        fi
    elif [[ $INSTALLER =~ ^gs:// ]]; then
        INSTALLER_URL="http://${INSTALLER#gs://}"
    elif [[ $INSTALLER =~ ^http[s]?:// ]]; then
        INSTALLER_URL="$INSTALLER"
    else
        if ! INSTALLER_URL="$($XLRINFRADIR/bin/installer-url.sh -d az "$INSTALLER")"; then
            echo >&2 "Failed to upload or generate a url for $INSTALLER"
            exit 1
        fi
    fi
fi

if [ -n "$INSTALLER_URL" ]; then
    INSTALLER_SAS_TOKEN="${INSTALLER_URL#*\?}"
    if [ -n "$INSTALLER_SAS_TOKEN" ]; then
        INSTALLER_SAS_TOKEN='?'"$INSTALLER_SAS_TOKEN"
        INSTALLER_URL="${INSTALLER_URL%\?*}"
    fi
fi

DEPLOY_COUNT=$(az deployment group list -g $CLUSTER -otsv | wc -l)
NOW=$(date +%Y%m%d%H%M)
if [ $DEPLOY_COUNT -eq 0 ]; then
    DEPLOY="$CLUSTER-deploy"
else
    DEPLOY="$CLUSTER-deploy-${NOW}-$DEPLOY_COUNT"
fi
EMAIL="${BUILD_USER_EMAIL:-$(id -un)@xcalar.com}"
set -e
for op in validate create; do
    deploy_name=
    if [ "$op" = create ]; then
        deploy_name="--name ${DEPLOY}"
    fi
    az deployment group $op --resource-group "$CLUSTER" $deploy_name --template-file "$TEMPLATE" \
        --parameters \
        @${PARAMETERS_DEFAULTS} \
        ${INSTALLER_URL:+installerUrl="$INSTALLER_URL"} \
        ${INSTALLER_SAS_TOKEN:+installerUrlSasToken="$INSTALLER_SAS_TOKEN"} \
        ${LICENSE:+licenseKey="$LICENSE"} \
        domainNameLabel="$CLUSTER" \
        customScriptName="$CUSTOM_SCRIPT_NAME" \
        bootstrapUrl="$BOOTSTRAP_URL" \
        adminEmail=$EMAIL \
        ${SHARE_NAME:+shareName="$SHARE_NAME"} \
        scaleNumber=$COUNT \
        appName=$CLUSTER ${INSTANCE_TYPE:+vmSize=$INSTANCE_TYPE} ${IMAGEID:+imageid=$(image_id $IMAGEID)}
done

az_privdns_update_ssh_hosts || true

$XLRINFRADIR/azure/azure-cluster-info.sh "$CLUSTER"
