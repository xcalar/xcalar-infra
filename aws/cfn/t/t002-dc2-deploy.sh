#!/bin/bash

DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
TMPDIR=$(mktemp -d /tmp/dc2-XXXXXX)
STACK_NAME=xdp-saas-$(id -un)-$(basename $0 .sh)-$(date +%Y%m%d%H%M)

onExit() {
    rc=$?
    if [ $rc -ne 0 ]; then
        aws cloudformation delete-stack --stack-name $STACK_NAME
        echo >&2 "Saved TMPDIR=$TMPDIR"
    else
        echo "StackName: $STACK_NAME"
        rm -rf $TMPDIR
    fi
    exit $rc
}
trap 'onExit' EXIT

set -a
. "${1:-${DIR}/xdp-saas.env}"
set +a

dc2 upload --environment ${ENVIRONMENT} \
           --project ${PROJECT} \
           --version ${VERSION} \
           --release ${RELEASE} \
           --image-id ${IMAGE_ID} ${DEBUG:+--debug} | cfn-flip | tee $TMPDIR/dc2.json

templateUrl_withvpc=$(jq -r .templateUrl_withvpc < $TMPDIR/dc2.json)

aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_IAM \
    --template-url $templateUrl_withvpc \
    --on-failure DELETE \
    --parameters "$(jq -r '.Parameters + [{ParameterKey:"CNAME",ParameterValue:"'$STACK_NAME'"}]' < $DIR/parameters.json)" \
    || die "Failed to launch stack $STACK_NAME from $templateUrl_withvpc"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
