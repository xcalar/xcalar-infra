#!/bin/bash
#
# Copies the manifest of a bucket to an output file.
# The manifests are gzip compressed .csv files.
# If no output file is specified, then the manifest
# is streamed to stdout

set -eo pipefail

# Overridable defaults
LOGS_BUCKET="${LOGS_BUCKET:-s3://xclogs}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-559166403383}"

# User args
BUCKET="${1:?Need to specify bucket}"
shift

# Fix inputs
BUCKET="${BUCKET##s3://}"
LOGS_BUCKET="${LOGS_BUCKET##s3://}"


INVENTORY_PREFIX=AWSLogs/${AWS_ACCOUNT_ID}/S3/${BUCKET}/inventory//${BUCKET}/${BUCKET}/
LATEST="$(aws s3 ls "s3://${LOGS_BUCKET}/${INVENTORY_PREFIX}"  | awk '/PRE 2/{print $(NF)}' | tail -1)"

MANIFEST="${INVENTORY_PREFIX}${LATEST}manifest.json"

INVENTORY="$(aws s3 cp "s3://${LOGS_BUCKET}/${MANIFEST}" - | jq -r '.files[].key')"

if [ -n "$2" ]; then
    aws s3 cp "s3://${LOGS_BUCKET}/${INVENTORY}" "${2}"
else
    aws s3 cp "s3://${LOGS_BUCKET}/${INVENTORY}" - | zcat
fi
