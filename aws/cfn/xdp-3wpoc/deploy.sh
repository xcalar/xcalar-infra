#!/bin/bash

set -e

S3_BUCKET=cfn-364047378361
S3_PREFIX=cfn/xdp-3wpoc/v1
TEMPLATE=xdp-single.template
export AWS_DEFAULT_REGION=us-east-1
export AWS_PROFILE=xcalar-poc

s3_cp() {
    aws s3 cp --cache-control 'no-cache, no-store, must-revalidate, max-age=0, no-transform' --acl public-read "$@"
}

s3_cp ../../r53update.sh s3://${S3_BUCKET}/cfn/scripts/
s3_cp ${TEMPLATE} s3://${S3_BUCKET}/${S3_PREFIX}/${TEMPLATE}

echo "https://s3.amazonaws.com/${S3_BUCKET}/${S3_PREFIX}/${TEMPLATE}"
