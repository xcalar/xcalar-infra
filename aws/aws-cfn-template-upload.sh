#!/bin/bash

set -eu

S3BUCKET=${S3BUCKET:-xcrepo}
S3REGION=${S3REGION:-us-west-2}
S3PATH=${S3PATH:-aws/cfn/}

aws_s3_upload_template() {
    if ! test -r "$1"; then
        echo >&2 "Unable to read $1"
        return 1
    fi
    aws s3 cp --acl public-read  \
        --metadata-directive REPLACE \
        --cache-control 'no-cache, no-store, must-revalidate, max-age=0, no-transform' \
        --content-type text/plain \
        --only-show-errors \
        "$1" "$2"
}

if ! command -v cfn-flip >/dev/null; then
    echo >&2 "Couldn't find cfn-flip. Please 'pip install -U cfn-flip"
    exit 1
fi

if ! cfn-flip < "$1" | cfn-flip >/dev/null; then
    echo >&2 "Failed to validate template with cfn-flip"
    exit 1
fi

DEST="${S3BUCKET}/${S3PATH}$(basename $1)"
URL="https://s3-${S3REGION}.amazonaws.com/${DEST}"
aws_s3_upload_template "$1" "s3://${DEST}" && \
    echo "$URL"
