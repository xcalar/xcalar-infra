#!/bin/bash

if [ -n "$1" ]; then
    CLUSTER="${1}"
    shift
else
    CLUSTER="`id -un`-xcalar"
fi

az group delete --name "$CLUSTER" -y
