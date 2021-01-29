#!/bin/bash

set -e

DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

. infra-sh-lib
. aws-sh-lib


export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
case "$AWS_DEFAULT_REGION" in
    us-east-1) BUCKET=xcrepoe1;;
    us-west-2) BUCKET=xcrepo;;
    *) die "Unsupported region: $AWS_DEFAULT_REGION";;
esac

set -u

VERSION=$(cat $DIR/VERSION)
RELEASE=$(cat $DIR/RELEASE)
PRODUCT=$(basename $DIR)

TEMPLATE=${TEMPLATE:-xdp-standard.template}
PREFIX=cfn/prod/${PRODUCT}/${VERSION}-${RELEASE}
URL_PREFIX=https://$(aws_s3_endpoint ${BUCKET})/${PREFIX%/}
TemplateUrl=${URL_PREFIX}/$(basename ${TEMPLATE} .template).yaml
BootstrapUrl=${URL_PREFIX}/scripts/user-data.sh
CustomScriptUrl=

check_url() {
    local http_code
    if ! http_code=$(curl -sL -o /dev/null -r 0-100 -w '%{http_code}\n' "$1"); then
        echo >&2 "$1 returned an error"
        return 1
    fi
    if ! [[ $http_code =~ ^20 ]]; then
        echo >&2 "$1 returned ${http_code}"
        return 1
    fi
}

aws_cfn() {
    local cmd="$1"
    shift
    echo aws cloudformation $cmd \
        --region ${AWS_DEFAULT_REGION} --capabilities CAPABILITY_IAM --on-failure DO_NOTHING \
        --parameters ParameterKey=VPCID,ParameterValue=vpc-30100e55 \
                    ParameterKey=ClusterInstanceType,ParameterValue=c5d.2xlarge \
                    ParameterKey=AssociatePublicIpAddress,ParameterValue=true \
                    ParameterKey=ClusterAccessSGId,ParameterValue=sg-01c9dd12946e730bc \
                    ParameterKey=KeyName,ParameterValue=xcalar-${AWS_DEFAULT_REGION} \
                    ParameterKey=VPCCIDR,ParameterValue=$(curl -s -4 http://icanhazip.com)/32 \
                    ParameterKey=PrivateSubnetCluster,ParameterValue=subnet-6a7d1641 \
                    ParameterKey=BootstrapUrl,ParameterValue="${BootstrapUrl}" \
                    ${CustomScriptUrl+ParameterKey=CustomScriptUrl,ParameterValue="${CustomScriptUrl}"} \
                    --template-body file://${TEMPLATE} "$@"
}

aws_s3_endpoint $BUCKET

check_url "$BootstrapUrl" || exit 1
check_url "$TemplateUrl" || exit 1
if [ -n "$CustomScriptUrl" ]; then
    check_url "$CustomScriptUrl" || exit 1
fi

aws cloudformation validate-template --template-body file://xdp-standard.template \
    && aws_cfn create-stack "$@"
