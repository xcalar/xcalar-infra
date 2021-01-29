#!/bin/bash

. infra-sh-lib

S3PREFIX=${S3PREFIX:-cfn/}
S3BUCKET=${S3BUCKET:-xcrepo}
ENVIRONMENT=${ENVIRONMENT:-dev}
VERSION=${VERSION:-1.0}
RELEASE=${RELEASE:-1}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --bucket=*) S3BUCKET="${cmd#*=}";;
        -b|--bucket) S3BUCKET="$1"; shift;;
        --prefix=*) S3PREFIX="${cmd#*=}";;
        --prefix) S3PREFIX="$1"; shift;;
        --env=*) ENVIRONMENT="${cmd#*=}";;
        -e|--env) ENVIRONMENT="$1"; shift;;
        --project=*) PROJECT="${cmd#*=}";;
        -p|--project) PROJECT="$1"; shift;;
        --release=*) RELEASE="${cmd#*=}";;
        -r|--release) RELEASE="$1"; shift;;
        --version=*) VERSION="${cmd#*=}";;
        --version) VERSION="$1"; shift;;
        --installer_version)
            installer_version="$1"
            VERSION="$1"
            shift
            ;;
        --installer_build_number)
            installer_build_number="$1"
            shift
            ;;
        --installer_rc)
            installer_rc="$1"
            shift
            ;;
        --installer_tag)
            TAG="$1"
            installer_tag="$1"
            shift
            ;;
        --image_build_number)
            image_build_number="$1"
            shift
            ;;
    esac
done

if [ -n "$PROJECT" ]; then
    cd $XLRINFRADIR/aws/cfn/$PROJECT || die "Invalid project: $PROJECT"
fi

if [ -z "$PROJECT" ]; then
    if [ "${PWD#$XLRINFRADIR/aws/cfn/}" = $(basename $PWD) ]; then
        PROJECT=$(basename $PWD)
    else
        die "Must specify project"
    fi
fi

if [ -z "$TAG" ]; then
    TAG="${VERSION}${RC}"
fi
echo "https://${S3BUCKET}.s3.amazonaws.com/${S3PREFIX}${ENVIRONMENT:+$ENVIRONMENT/}${PROJECT:+$PROJECT/}${TAG}"
