#!/bin/bash
# This script is not completed because the item gets punted

set -ex
export XLRINFRADIR=${XLRINFRADIR-$HOME/xcalar-infra}
export XLRGUIDIR=${XLRGUIDIR-$XLRINFRADIR/xcalar-gui}

if ! aws s3 ls ${S3_BUCKET}; then
    aws s3 mb "s3://${S3_BUCKET}" --region ${AWS_REGION}
fi

MAIN_URL=`aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/main/${MAIN_LAMBDA_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^".*XCE_SAAS_MAIN_LAMBDA_URL=//' -e 's/\\\\n.*"$//' -e 's/"$//' -e 's/\/$//'`
AUTH_URL=`aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/auth/${AUTH_LAMBDA_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^".*XCE_SAAS_AUTH_LAMBDA_URL=//' -e 's/\\\\n.*"$//' -e 's/"$//' -e 's/\/$//'`
USER_POOL_ID=`aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/auth/${AUTH_LAMBDA_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^".*XCE_CLOUD_USER_POOL_ID=//' -e 's/\\\\n.*"$//' -e 's/"$//' -e 's/\/$//'`
CLIENT_ID=`aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/auth/${AUTH_LAMBDA_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^".*XCE_CLOUD_CLIENT_ID=//' -e 's/\\\\n.*"$//' -e 's/"$//' -e 's/\/$//'`

echo "Building XD"
cd $XLRGUIDIR
npm install --save-dev
node_modules/grunt/bin/grunt init
node_modules/grunt/bin/grunt cloud_login --XCE_SAAS_MAIN_LAMBDA_URL=${MAIN_URL} --XCE_SAAS_AUTH_LAMBDA_URL=${AUTH_URL} --XCE_CLOUD_USER_POOL_ID=${USER_POOL_ID} --XCE_CLOUD_CLIENT_ID=${CLIENT_ID}

aws s3 sync --acl public-read ${XLRGUIDIR}/xcalar-gui/cloudLogin s3://${S3_BUCKET}/${TARGET_PATH} --region ${AWS_REGION}
aws s3 sync --acl public-read ${XLRGUIDIR}/xcalar-gui/ s3://${S3_BUCKET}/${TARGET_PATH} --exclude "*" --include "favicon.ico" --include "*assets/fonts/*" --include "*assets/js/cloudConstants.js" --region ${AWS_REGION}
aws cloudfront create-invalidation --distribution-id ${DISTRIBUTION_ID} --paths /${TARGET_PATH}