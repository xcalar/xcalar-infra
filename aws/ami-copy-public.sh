#!/bin/bash
#
# Copy a set of source image in one region to another
# optionally waiting for them and making them public
#
# ami-copy-public.sh

SOURCE_AMIS=()
REGION=us-east-1
SOURCE_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
WAIT=0
PUBLIC=0

usage () {
    cat >&2 <<EOF
usage: $0 [--source-image-id <image-id>] [--source-region <region: default $AWS_DEFAULT_REGION>] [--region <dest region: default $REGION>] [--wait] [--public]  [--] ami-12344 ...

    Will copy the specified image-id(s) from source-region to region. If --wait is specified, the program will wait for the
    images to become available. Specifying --public implied --wait and will markt he destination ami as public.
EOF
    exit 1
}

wait_and_maybe_public () {
    local image_id= rc= ii=
    aws ec2 wait image-available --region $REGION --image-ids "$@"
    rc=$?
    if [ "$PUBLIC" != 1 ]; then
        return $rc
    fi
    for image_id in "$@"; do
        for(( ii=0; ii<5; ii++)); do
            if aws ec2 modify-image-attribute --image-id $image_id --region $REGION --launch-permission "{\"Add\":[{\"Group\":\"all\"}]}"; then
                echo >&2 "Made $image_id ($REGION) public"
                break
            fi
            echo >&2 "Waiting for $image_id .."
            sleep 10
        done
    done
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -h|--help) usage;;
        --source-image-id) SOURCE_AMIS+=($1); shift;;
        --source-region) SOURCE_REGION=$1; shift;;
        --region) REGION=$1; shift;;
        --wait) WAIT=1;;
        --public) PUBLIC=1;;
        ami-*) SOURCE_AMIS+=($cmd);;
        --) break;;
        *) usage;;
    esac
done

if [ $# -gt 0 ]; then
    SOURCE_AMIS+=($@)
    shift $#
fi

if [ "${#SOURCE_AMIS[@]}" -eq 0 ]; then
    usage
fi

DEST_AMIS=()
for SOURCE in "${SOURCE_AMIS[@]}"; do
    NAME="$(aws ec2 describe-images --image-ids $SOURCE --query 'Images[0].Name' --output text)"
    if DEST=$(aws ec2 copy-image --source-image-id $SOURCE --source-region $SOURCE_REGION --region $REGION --name "$NAME" --query ImageId --output text); then
        if [[ $DEST =~ ^ami- ]]; then
            echo >&2 "Copying $SOURCE ($SOURCE_REGION) -> $DEST ($REGION)"
            DEST_AMIS+=($DEST)
        else
            echo >&2 "Invalid AMI: $DEST"
            continue
        fi
    else
        echo >&2 "Failed to copy $SOURCE to $REGION"
        continue
    fi
done

if [ "$WAIT" = 1 -o "$PUBLIC" = 1 ]; then
    wait_and_maybe_public "${DEST_AMIS[@]}"
fi
