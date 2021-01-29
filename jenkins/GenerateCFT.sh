#!/bin/bash

set -e

export XLRINFRADIR=$PWD
export PATH=$XLRINFRADIR/bin:$PATH
source bin/activate
source infra-sh-lib
mkdir -p output
rm -f output/*
curl -fsLO https://jenkins.int.xcalar.com/job/Packer/lastSuccessfulBuild/artifact/output/packer-manifest.json

AMI_ID=$(packer_query_manifest amazon-ebs-amzn2 packer-manifest.json | grep -Eow 'us-west-2:ami-[0-9a-f]+' | tail -1)
AMI_ID="${AMI_ID#us-west-2:}"
dc2 upload --project $PROJECT --env $ENVIRONMENT \
    --manifest packer-manifest.json \
    --url-file output/output.url $(installer-version.sh --format=clieq $AMI_ID)
