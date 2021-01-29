#!/bin/bash

set -e

. infra-sh-lib

OWNER=${OWNER:-$(id -un)}
LOCATION=${LOCATION:-westus2}
EMAIL=$(git config user.email)
TAGS=" --tags email=$EMAIL owner=$OWNER"

ok_or_not() {
    local res=$1
    shift
    if [ $res -eq 0 ]; then
        echo "ok $*"
    else
        echo "not ok $*"
    fi
}

test_setup() {
    NOW=$(date +%Y%m%d%H%M)
    declare -g -A RG=([T0]=$OWNER-test01-rg [T1]=$OWNER-test02-rg [IP]=xdp-$OWNER-rg [SA]=xdp-$OWNER-rg)
    declare -g -A NAME=([T0]=$OWNER-test01-cluster [T1]=$OWNER-test02-cluster [IP]=$OWNER-ip [SA]=xdp${OWNER}sa)

    dnsName="$(az network public-ip show -g ${RG[IP]} -n ${NAME[IP]} -ojson --query 'dnsSettings.domainNameLabel' -otsv)"
    if test -z "$dnsName"; then
        az group create -l $LOCATION -g ${RG[IP]} $TAGS
        az network public-ip create -l $LOCATION -g ${RG[IP]} -n ${NAME[IP]} --allocation-method Dynamic --dns-name ${NAME[IP]} $TAGS
        dnsName="$(az network public-ip show -g ${RG[IP]} -n ${NAME[IP]} -ojson --query 'dnsSettings.domainNameLabel' -otsv)"
    fi
    test "$dnsName" = "${NAME[IP]}"
    ok_or_not $? 1 - "IP address is $dnsName (should be ${NAME[IP]})"
    storageUri="$(az storage account show -g ${RG[SA]} -n ${NAME[SA]} -ojson --query 'primaryEndpoints.blob' -otsv)"
    if test -z "$storageUri"; then
        az group create -l $LOCATION -g ${RG[SA]} $TAGS
        az storage account create -l $LOCATION -g ${RG[SA]} -n ${NAME[SA]} --sku Standard_LRS --kind StorageV2 $TAGS
        storageUri="$(az storage account show -g ${RG[SA]} -n ${NAME[SA]} -ojson --query 'primaryEndpoints.blob' -otsv)"
    fi
    test "$storageUri" = "https://${NAME[SA]}.blob.core.windows.net/"
    ok_or_not $? 2 - "Storage URI is $storageUri (should be https://${NAME[SA]}.blob.core.windows.net/)"
}

az_deploy() {
    az deployment group validate \
        --template-file mainTemplate.json \
        --mode complete "$@" \
        && az deployment group create --name my-deploy \
            --template-file mainTemplate.json \
            --mode complete "$@"
}

set +e

echo "1..4"

test_setup

az group delete --yes -g ${RG[T0]} 2>/dev/null || true
az group create -l $LOCATION -g ${RG[T0]} $TAGS
az_deploy -g ${RG[T0]} \
    --parameters @parameters/01-newSAandIP.parameters.json \
    --parameters domainNameLabel=$OWNER-new-ip -ojson | tee ${RG[T0]}-deploy.json
ok_or_not ${PIPESTATUS[0]} 3 "- Deploy ${RT[0]}"

az group delete --yes -g ${RG[T1]} 2>/dev/null || true
az group create -l $LOCATION -g ${RG[T1]} $TAGS
az_deploy -g ${RG[T1]} -ojson \
    --parameters @parameters/02-existingSAandIP.parameters.json \
    --parameters \
    domainNameLabel=${NAME[IP]} \
    publicIpAddressRG=${RG[IP]} \
    publicIpAddressName=${NAME[IP]} \
    publicIpAddressNewOrExisting=existing \
    storageAccountRG=${RG[SA]} \
    storageAccountName=${NAME[SA]} \
    storageAccountNewOrExisting=existing \
    | tee ${RG[T1]}-deploy.json
ok_or_not ${PIPESTATUS[0]} 4 "- Deploy ${RT[1]}"

exit $?
