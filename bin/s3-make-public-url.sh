#!/bin/bash

set -e

S3URL="${1?Need to specify s3url}"
BODY="$2"

S3URL="${S3URL#s3://}"

BUCKET="${S3URL%%/*}"
KEY="${S3URL#*/}"

if [ -n "$BODY" ]; then
  ARGS=()
  EXT="${KEY##*.}"
  case "$EXT" in
    yml|yaml|json|txt) ARGS+=(--content-type text/plain);;
  esac
  aws s3api put-object --acl public-read --body "${BODY}" --bucket "${BUCKET}" "${ARGS[@]}" --key "${KEY}"
else
  aws s3api put-object-acl --acl public-read --bucket "${BUCKET}" --key "${KEY}"
fi

echo "https://${BUCKET}.s3.amazonaws.com/${KEY}"
