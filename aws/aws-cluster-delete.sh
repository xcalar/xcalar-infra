#!/bin/bash

CLUSTER="${1:?Need to specify Cfn cluster name}"

aws cloudformation delete-stack --stack-name "${1}"
