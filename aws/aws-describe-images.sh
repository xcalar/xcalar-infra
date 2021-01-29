#!/bin/bash

set -e

TMPDIR="${TMPDIR:-/tmp}/$LOGNAME/aws"
mkdir -p "$TMPDIR"
IMAGESJSON="$TMPDIR/images$$.json"
IMAGESCSV="$TMPDIR/images$$.csv"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"

if ! command -v aws &>/dev/null; then
    echo >&2 "Need to install awscli..."
    sudo pip install -U awscli
fi
aws ec2 describe-images --owners=self > "$IMAGESJSON"
jq -r '.Images[]|[.ImageId,.Name,.BlockDeviceMappings[0].Ebs.SnapshotId]|@tsv' < "$IMAGESJSON" > "$IMAGESCSV"


while read ami name snapshot; do
    echo "AMI: $ami name: $name snapshot: $snapshot"
    aws ec2 create-tags --resources "$snapshot" --tags "Key=Name,Value=$name"
done < "$IMAGESCSV"
