#!/bin/bash

# Inputs:
# REGION (maps to: AWS_REGION)
# S3_BUCKET
# CLOUDFORMATION_STACK_NAME

set -ex
export AWS_DEFAULT_REGION=us-west-2
export AWS_REGION="${REGION:-$AWS_DEFAULT_REGION}"
export XLRINFRADIR=${XLRINFRADIR-$HOME/xcalar-infra}
SAAS_AUTH_DIR="$XLRINFRADIR/aws/lambdaFns/saas/saas-auth"

PATH=/opt/xcalar/bin:$PATH
export PATH

if ! aws s3api get-bucket-location --bucket ${S3_BUCKET} \
         --region ${AWS_REGION}; then
    aws s3 rb s3://${S3_BUCKET} --region ${AWS_REGION} --force
    aws s3api wait bucket-not-exists --bucket ${S3_BUCKET}
fi

(cd "$SAAS_AUTH_DIR" &&
     aws cloudformation delete-stack \
         --stack-name ${CLOUDFORMATION_STACK_NAME} \
         --region ${AWS_REGION})
