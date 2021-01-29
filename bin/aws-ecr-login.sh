#!/bin/bash

ACCOUNT_ID=${ACCOUNT_ID:-559166403383}
aws ecr get-login-password --region ${AWS_DEFAULT_REGION} \
    | docker login \
    --username AWS \
    --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
