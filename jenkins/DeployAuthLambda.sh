#!/bin/bash

# Inputs:
# REGION (maps to: AWS_REGION)
# S3_BUCKET
# ACCOUNT_ID
# FUNCTION_NAME
# USER_TABLE_NAME
# SESSION_TABLE_NAME
# IDENTITY_POOL_ID
# USER_POOL_ID
# CLIENT_ID
# CLOUDFORMATION_STACK_NAME
# CORS_ORIGIN

set -ex
export AWS_DEFAULT_REGION=us-west-2
export AWS_DEFAULT_FNAME="AwsServerlessExpressFunction"
export AWS_REGION="${REGION:-$AWS_DEFAULT_REGION}"
export XLRINFRADIR=${XLRINFRADIR-$HOME/xcalar-infra}
SAAS_AUTH_DIR="$XLRINFRADIR/aws/lambdaFns/saas/saas-auth"
export TMPDIR=/tmp/`id -un`/DeployAuthLambda

mkdir -p $TMPDIR

export STATUS_FILE=${TMPDIR}/DeployAuthLambda.$$

PATH=/opt/xcalar/bin:$PATH
export PATH

if ! aws s3api get-bucket-location --bucket ${S3_BUCKET} \
         --region ${AWS_REGION}; then
    aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION}
fi

(cd "$SAAS_AUTH_DIR" &&
     /opt/xcalar/bin/node \
         ./scripts/configure.js \
         --account-id ${ACCOUNT_ID} --bucket-name ${S3_BUCKET} \
         --function-name ${FUNCTION_NAME:-$AWS_DEFAULT_FNAME} \
         --region ${AWS_REGION} \
         --user-table-name ${USER_TABLE_NAME} \
         --session-table-name ${SESSION_TABLE_NAME} \
         --creds-table-name ${CREDS_TABLE_NAME} \
         --identity-pool-id ${IDENTITY_POOL_ID} \
         --user-pool-id ${USER_POOL_ID} \
         --client-id ${CLIENT_ID} \
         --cloudformation-stack ${CLOUDFORMATION_STACK_NAME} \
         --cors-origin ${CORS_ORIGIN} &&
     /opt/xcalar/bin/npm install &&
     /opt/xcalar/bin/npm uninstall passport-cognito --no-save &&
     /opt/xcalar/bin/npm install ./passport-cognito-1.0.0.tgz &&
     aws cloudformation package --template ./cloudformation.yaml \
         --s3-bucket ${S3_BUCKET} --output-template ./packaged-sam.yaml \
         --region ${AWS_REGION} &&
     aws cloudformation deploy --template-file packaged-sam.yaml \
         --stack-name ${CLOUDFORMATION_STACK_NAME} \
         --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --region ${AWS_REGION} \
         --role-arn ${ROLE} && echo '0' > "$STATUS_FILE" ||
         echo '1' > "$STATUS_FILE")

DEPLOY_STATUS="$(cat "$STATUS_FILE")"

if [ "0" == "$DEPLOY_STATUS" ]; then
    API_URL="$(aws cloudformation describe-stacks \
                  --region ${AWS_REGION} \
                  --stack-name ${CLOUDFORMATION_STACK_NAME} \
                  --query "Stacks[*].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
                  --output text)"
    PARAM_STR="XCE_CLOUD_MODE=1\nXCE_CLOUD_SESSION_TABLE=${SESSION_TABLE_NAME}\nXCE_CLOUD_USER_POOL_ID=${USER_POOL_ID}\nXCE_CLOUD_CLIENT_ID=${CLIENT_ID}\nXCE_SAAS_AUTH_LAMBDA_URL=${API_URL}\nXCE_CLOUD_REGION=${AWS_REGION}\nXCE_CLOUD_PREFIX=xc\nXCE_CLOUD_HASH_KEY=id\n"
else
    aws cloudformation describe-stack-events --stack-name ${CLOUDFORMATION_STACK_NAME}
fi

rm -f "$STATUS_FILE"

# we want to deconfigure no matter what
(cd "$SAAS_AUTH_DIR" &&
     /opt/xcalar/bin/node ./scripts/deconfigure.js)

exit $DEPLOY_STATUS
