#!/bin/bash

IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)

get_mds() {
    if [ -n "$IMDSV2_TOKEN" ]; then
        curl -fsSL -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/latest/${1#/}"
    else
        curl -fsSL  http://169.254.169.254/2020-10-27/"${1#/}"
    fi
}

INSTANCE_ID=$(get_mds meta-data/instance-id)
AVZONE=$(get_mds meta-data/placement/availability-zone)
export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"
AMI_LAUNCH_INDEX=$(get_mds meta-data/ami-launch-index)
set -o pipefail
aws ec2 describe-instances --region ${AWS_DEFAULT_REGION} --instance-ids $INSTANCE_ID --query 'Reservations[].Instances[].Tags[*]' --output text | tr '\t' '=' | tr ':' '_' | sed -r 's/^([A-Za-z_]+)=/\U\1=/g'
cat << EOF
INSTANCE_ID=$INSTANCE_ID
AVZONE=$AVZONE
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
AWS_REGION=${AWS_DEFAULT_REGION}
AMI_LAUNCH_INDEX=$AMI_LAUNCH_INDEX
EOF

