#!/bin/bash

if [ -n "$1" ]; then
    CLUSTER="${1}"
    shift
else
    CLUSTER="$(id -un)-xcalar"
fi

DEPLOY="$CLUSTER-deploy"
DEPLOY=$(az deployment group list -g ${CLUSTER} -otsv | head -1 | awk '{print $3}')

DEPLOY_JSON=$(az deployment group show --resource-group "$CLUSTER" --name "$DEPLOY" --output json)
provisioningState=$(jq -r .properties.provisioningState <<<$DEPLOY_JSON)
if [ "$provisioningState" != Succeeded ]; then
    echo >&2 "ERROR: $DEPLOY failed"
    exit 1
fi
count=$(jq -r .properties.outputs.scaleNumber.value <<<$DEPLOY_JSON)
domainNameLabel=$(jq -r .properties.outputs.domainNameLabel.value <<<$DEPLOY_JSON)
location=$(jq -r .properties.outputs.location.value <<<$DEPLOY_JSON)

#count=`az deployment group show --resource-group "$CLUSTER" --name "$DEPLOY" --output json --query 'properties.outputs.scaleNumber.value' --output tsv`
#domainNameLabel=`az deployment group show --resource-group "$CLUSTER" --name "$DEPLOY" --output json --query 'properties.outputs.domainNameLabel.value' --output tsv`
#location=`az deployment group show --resource-group "$CLUSTER" --name "$DEPLOY" --output json --query 'properties.outputs.location.value' --output tsv`
for ii in $(seq 0 $((count - 1))); do
    echo "${CLUSTER}-vm${ii}.azure"
done
