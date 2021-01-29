#!/bin/bash

while [ $# -gt 0 ]; do
    case "$1" in
        --stack) STACK="$2"; shift 2;;
        --) shift; break ;;
        -*) echo >&2 "ERROR: Unknown argument: $1"; exit 2;;
    esac
done

if [ -z "$STACK" ]; then
    STACK=${USER}-stack
fi

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

aws --profile xcalar-poc cloudformation deploy --template-file xdp-single.template --stack-name ${STACK} \
    --role-arn arn:aws:iam::364047378361:role/AWS-For-Users-CloudFormation \
    --capabilities CAPABILITY_IAM \
    --s3-bucket cfn-364047378361 \
    --s3-prefix cfn/debug \
    --tags Owner="${OWNER:-$USER}" \
           CallerArn="$(aws sts get-caller-identity --query Arn --output text)" \
           GitEmail="$(git config user.email)" \
    --parameter-overrides $(cat xdp-single.params) "$@"
