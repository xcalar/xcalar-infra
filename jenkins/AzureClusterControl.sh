#!/bin/bash

set +x
export XLRINFRADIR=$PWD
export PATH=$PWD/bin:/opt/xcalar/bin:$PATH
source $XLRINFRADIR/azure/azure-sh-lib

az_login

if ! [[ $CLUSTER_NAME =~ ^xdp- ]]; then
    echo >&2 "Cluster name must begin with xdp-"
    exit 1
fi

found=false
for groupName in ${CLUSTER_NAME} ${CLUSTER_NAME%-rg}-rg ${CLUSTER_NAME}-rg ${CLUSTER_NAME%-*} ${CLUSTER_NAME%-*}-rg; do
    if az group show -g "$groupName"; then
        found=true
        break
    fi
done

if [ "$found" != true ]; then
    echo >&2 "Couldn't find a cluster with that name: $CLUSTER_NAME"
    exit 1
fi

case "$RG_COMMAND" in
    delete)
        az group delete -g "${groupName}" --yes
        ;;
    scheduled_shutdown)
        az_rg_scheduled_shutdown -g "${groupName}" --time "${TIME:-2300}" --timezone "${TIMEZONE:-pst}" --enabled "${AUTOSHUTDOWN:-true}"
        ;;
    *)
        az_rg_${RG_COMMAND} "${groupName}"
        ;;
esac
exit $?
