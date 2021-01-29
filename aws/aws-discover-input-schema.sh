#!/bin/bash

aws_meta() {
    curl --connect-timeout 2 --fail --silent http://169.254.169.254/2018-09-24/meta-data/"$1"
}

discover() {
    local key="$1"
    local bucket
    if [[ $key =~ ^s3:// ]]; then
        key="${key#s3://}"
        bucket="${key%%/*}"
        key="${key#${bucket}/}"
    elif [[ $key =~ ^/ ]]; then
        bucket="${key#/}"
        bucket="${bucket%%/*}"
        key="${key#/${bucket}/}"
    else
        bucket="${BUCKET:?Must specify bucket via -b or path with /bucket/}"
    fi

    if ! aws kinesisanalytics discover-input-schema \
        --s3-configuration RoleARN=${KINESISROLEARN},BucketARN=arn:aws:s3:::${bucket},FileKey="$key"; then
            echo >&2 "ERROR: Unable to read they key $key in bucket $bucket  (s3://${bucket}/${key})"
        return 1
    fi
}

load_env() {
    set -a
    if test -r ec2.env; then
        . ec2.env 2>/dev/null
    elif test -r /var/lib/cloud/instance/ec2.env; then
        . /var/lib/cloud/instance/ec2.env 2>/dev/null
    else
        echo >&2 "WARNING: Neither /var/lib/cloud/instance/ec2.env or ec2.env could be read"
    fi
    set +a
}

strjoin() {
    local IFS="$1"
    shift
    echo "$*"
}

main() {
    if [ -z "$AWS_DEFAULT_REGION" ]; then
        if AVZONE=$(aws_meta placement/availability-zone); then
            export AWS_DEFAULT_REGION="${AVZONE%[a-i]}"
        else
            export AWS_DEFAULT_REGION="us-west-2"
        fi
    fi

    local filter=()
    [ -n "$BUCKET" ] && filter+=('BUCKET')
    [ -n "$KINESISROLEARN" ] && filter+=('KINESISROLEARN')
    grepFilter="(\"\$(strjoin '|' \"${filter[*]}\")\")"

    [ $# -gt 0 ] || set -- --help
    while [ $# -gt 0 ]; do
        cmd="$1"
        case "$cmd" in
            -h | --help)
                echo "Usage $0 [-r roleArn] /bucket/key1 /bucket/key2 ..."
                echo "      $0 [-r roleArn] -b bucket key1 key2 ..."
                exit 0
                ;;
            -b | --bucket)
                readonly BUCKET="$2"
                shift 2
                ;;
            -r | --role)
                readonly KINESISROLEARN="$2"
                shift 2
                ;;
            *) break ;;
        esac
    done
    load_env

    test -n "$KISESISROLEARN" || KISESISROLEARN="arn:aws:iam::559166403383:role/abakshi-instamart-KinesisServiceRole-K6TURBTVX2EF}"
    for ii in "$@"; do
        discover "$ii"
    done
}

main "$@"
