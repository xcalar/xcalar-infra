#!/bin/bash
#
# Create an AWS Cloudformation Stack for Field Demos
#
# Usage:
#  ./aws-cfn-single-node.sh [node-count (default:2)] [instance-type (default: c3.8xlarge)]
#
# c3.8xlarge = 32 vCPUs x 60GB x 600GB SSD = $1.680/hr
# r3.8xlarge = 32 vCPUs x 244GB x 600GB SSD = $2.660/hr
#
# Note: modify aws-setup to use the 600GB RAID0 command for r3.8xlarge, c3.8xlarge has 300GB
#
# Compare EC2 instance types for CPU, RAM, SSD with this calculator:
# http://www.ec2instances.info/?min_memory=60&min_vcpus=32&min_storage=1&region=us-west-2)
#
XLRINFRADIR="$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)"
NOW=$(date +%Y%m%d%H%M)
STACK_NAME=${LOGNAME}-single-node-${NOW}
TEMPLATE="${PWD}/cfn/XCE-CloudFormationSingleNodeForCustomers.yaml"
INSTALLER_URL="${1:-s3://xcrepo/builds/c94df876-5ab9a93c/prod/xcalar-1.2.2-1236-installer}"
INSTANCE_TYPE="${2:-i3.2xlarge}"
LICENSE="$(cat license.key)"
#export AWS_DEFAULT_REGION=us-east-1

INSTALLER_URL="$($XLRINFRADIR/bin/installer-url.sh -d s3 "$INSTALLER_URL")"

http_code="$(curl -sI -X GET -o /dev/null -w '%{http_code}\n' "$INSTALLER_URL")"
if ! [[ "$http_code" =~ ^20 ]]; then
    echo >&2 "ERROR($http_code): Failed to download url: $INSTALLER_URL"
    exit 1
fi

PARMS=(\
InstallerUrl    "$INSTALLER_URL"
AdminUsername   xcalar
AdminPassword   Welcome1
AdminEmail      "$(git config user.email)"
InstanceType	  ${INSTANCE_TYPE}
KeyName	        xcalar-us-east-1
CidrLocation	  0.0.0.0/0
VpcId	          vpc-30100e55
Subnet	        subnet-e55cc480
RootSize        250
LicenseKey      "${LICENSE}")

ARGS=()
for ii in $(seq 0 2 $(( ${#PARMS[@]} - 1)) ); do
    k=$(( $ii + 0 ))
    v=$(( $ii + 1 ))
    ARGS+=(ParameterKey=${PARMS[$k]},ParameterValue=\"${PARMS[$v]}\")
done

set -e
aws cloudformation validate-template --template-body file://${TEMPLATE}
aws cloudformation create-stack \
        --stack-name ${STACK_NAME} \
        --template-body file://${TEMPLATE} \
        --timeout-in-minutes 15 \
        --on-failure DELETE \
        --tags \
            Key=Name,Value=${STACK_NAME} \
            Key=Owner,Value=${LOGNAME} \
        --parameters "${ARGS[@]}"
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME}
aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[].Outputs[].[Description,OutputKey,OutputValue]' --output table
