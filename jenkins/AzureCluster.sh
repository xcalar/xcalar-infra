#!/bin/bash
if [ -z "$XLRINFRADIR" ]; then
    XLRINFRADIR="$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)"
fi
export XLRINFRADIR
export PATH=$XLRINFRADIR/bin:$PATH

source $XLRINFRADIR/bin/infra-sh-lib || exit 1
source $XLRINFRADIR/azure/azure-sh-lib || exit 1

if [ -n "$AZURE_CLIENT_ID" ]; then
    az_login
fi

if [ "${INSTALLER_URL:0:1}" == / ]; then
    echo "Uploading $INSTALLER_URL to Azure Blobstore..."
    INSTALLER_URL="$(installer-url.sh -d az $INSTALLER_URL)" || exit 1
fi
echo "Installer: $INSTALLER_URL"

sanitize() {
    tr '[:upper:]' '[:lower:]' | tr '_./ ' '-' | sed -r 's/([-]+)/-/g'
}

if [ -z "$APP" ]; then
    if [ -n "$GROUP" ]; then
        APP="$GROUP"
    else
        if [ -n "$BUILD_USER_ID" ]; then
            APP="xdp-${BUILD_USER_ID}-${BUILD_NUMBER}"
        else
            APP="xdp-${JOB_NAME}-${BUILD_NUMBER}"
        fi
    fi
fi

APP="$(echo $APP | sanitize)"
APP="${APP#xdp-}"
APP="xdp-${APP}"

GROUP="${GROUP:-$APP}"
GROUP="${GROUP%-rg}"
GROUP="${GROUP#xdp-}"
GROUP="xdp-${GROUP}-rg"

set -e

LOCATION=${LOCATION:-westus2}

if ! az group show -g $GROUP > /dev/null 2>&1; then
    say "Creating a new resource group $GROUP"

    az group create -g $GROUP -l $LOCATION -ojson > /dev/null
    trap "az group delete -g $GROUP --no-wait -y" EXIT
fi

ADMIN_USERNAME=${ADMIN_USERNAME:-xdpadmin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Welcome1}

cd $XLRINFRADIR/azure
TIME="${TIME//:/}"
if ! az_deploy -g $GROUP -l $LOCATION -i "$INSTALLER_URL" --count $NUM_NODES \
    --size $INSTANCE_TYPE --name "$APP" ${CLUSTER:+--cluster $CLUSTER} \
    --timezone "${TIMEZONE:-Pacific Standard Time}" --time "${TIME:-2300}" \
    --parameters \
    adminEmail="${BUILD_USER_EMAIL:-nobody@xcalar.com}" \
    appUsername="$ADMIN_USERNAME" \
    appPassword="$ADMIN_PASSWORD" \
    licenseKey="$LICENSE_KEY" > output.json; then
    cat output.json >&2
    echo >&2 "Failed to deploy your template"
    exit 1
fi

az_privdns_update_ssh_hosts || true

URL="https://${APP}.${LOCATION}.cloudapp.azure.com"

echo "Login at $URL using User: ${ADMIN_USERNAME}, Password: ${ADMIN_PASSWORD}"

echo $URL > url.txt

trap '' EXIT
exit 0
