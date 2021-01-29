#!/bin/bash

set -ex

export AWS_DEFAULT_REGION=us-west-2

aws ssm put-parameter --tier Standard --type String --name "${SSM_KEY}" --value "${CFN_TEMPLATE_URL}" --overwrite