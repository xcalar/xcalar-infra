#!/bin/bash
#
# Publishes a lambda .zip packages to multiple
# regions as required by AWS. We use a bucket
# with our account-id and the region as a suffix.
# eg: sharedinf-lambdabucket-555-us-west-2, as it
# allows for easier use in CloudFormation.
#
# shellcheck disable=SC2206,SC2086

. infra-sh-lib
. aws-sh-lib


usage() {

    cat <<-EOF
    $0 [--regionless-bucket \$1] [--all-regions] [--copy-to-region]
        [--prefix <prefix>] [--file <file>] [--suffix SUFF] [-h|--help|--usage]

	EOF
}

main() {
    BUCKET_PREFIX="${BUCKET_PREFIX:-sharedinf-lambdabucket-559166403383}"
    BUCKETS=()
    REGIONS="${REGIONS:-$AWS_DEFAULT_REGION}"
    PREFIX=''
    SUFFIX=''
    KEY=''
    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            -b|--bucket) BUCKETS=("$1"); shift;;
            --regionless-bucket) BUCKET_PREFIX="$1"; shift;;
            --all-regions) REGIONS='us-west-2 us-west-1 us-east-1 us-east-2';;
            --copy-to-regions) REGIONS="$1"; shift;;
            --prefix)
                [ -z "$2" ] || PREFIX="${1%/}/"
                shift;;
            --key) KEY="$1"; shift;;
            --file) FILE="$1"; shift;;
            --suffix) SUFFIX="$1"; shift;;
            -h|--help) usage; exit 0;;
            *) usage >&2; echo >&2 "$0: Unknown command $cmd"; exit 2;;
        esac
    done
    if ! test -e "$FILE"; then
        die "Must specify an input file"
    fi
    REGIONS=(${REGIONS//,/ })

    MD5="$(md5sum < "$FILE" | cut -d' ' -f1)"
    if [ -z "${KEY}" ]; then
        KEY="${PREFIX}${MD5}${SUFFIX}"
    fi

    if [ -z "${BUCKETS[*]}" ]; then
        for region in "${REGIONS[@]}"; do
            BUCKETS+=(${BUCKET_PREFIX}-${region})
        done
    fi

    for bucket in "${BUCKETS[@]}"; do
        region=$(aws s3api get-bucket-location --bucket $bucket --query LocationConstraint --output text)
        if [ "$region" = None ]; then
            region=us-east-1
        fi
        if key="$(aws --region "$region" s3api list-objects-v2 --bucket "$bucket" --prefix "$KEY" --max-items 1 --query 'Contents[].Key' --output text)"; then
            if [ "$key" != None ]; then
                echo >&2 " + s3://${bucket}/${key} exists"
                continue
            fi
        fi
        aws --region "$region" s3 cp --quiet --acl public-read "$FILE" "s3://${bucket}/${KEY}" >&2
    done
    echo "$KEY"
}

main "$@"
