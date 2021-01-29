#!/bin/bash

for ii in $(seq "${#BASH_SOURCE[@]}"); do
    echo "\${BASH_SOURCE[$((ii-1))]} = \"${BASH_SOURCE[$((ii-1))]}\""
done

. "$XLRINFRADIR"/bin/infra-sh-lib </dev/null || { echo >&2 "ERROR: Couldn't source infra-sh-lib"; return 1; }

AWS_CFN_REF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aws_cfn_ref_do_list_types() {
    jq -r '.PropertyTypes|keys'
}

aws_cfn_ref_find_resource_index () {
    jq -r "$1|keys|to_entries|.[]|select(.value==\"$2\")|.key"
}

aws_cfn_ref() {
    local index=$(aws_cfn_ref_find_resource_index '.ResourceTypes' "$1")
    echo "$index"
}

aws_cfn_ref_resource_props() {
    jq -r "$1"'|to_entries[]|select(.key=="'"$2"'")|{Properties: .value|.Properties|to_entries|map_values({Name: .key} + .value)}'
}
test_aws_cfn_ref () {
    aws_cfn_ref_resource_props ".ResourceTypes" AWS::S3::Bucket < "$AWS_CFN_REF_JSON"
}

aws_cfn_ref_init () {
    AWS_CFN_REF_JSON="${XLRINFRADIR}/aws/cfn/reference/CloudFormationResourceSpecification.json"
}

aws_cfn_ref_init
