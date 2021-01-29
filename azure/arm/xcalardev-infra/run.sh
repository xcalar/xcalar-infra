#!/bin/bash

set -e
if [ -z "$1" ]; then
    echo >&2 "Specify VM name"
    exit 1
fi

RG=xcalardev-jenkins-slave-$1-rg
VM=jenkins-slave-el7-$1-vm

az group create -g $RG -l westus2
az deployment group validate -g $RG --template-file jenkins-slave.json --parameters @jenkins-slave.parameters.json virtualMachineName=$VM
az deployment group create -n deploy1 -g $RG --template-file jenkins-slave.json --parameters @jenkins-slave.parameters.json virtualMachineName=$VM
