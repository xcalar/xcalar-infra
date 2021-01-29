#!/bin/bash

eval_creds() {
    eval $(sed -n '/^ASUP/p; /^set_keys/,/^}/p;' /opt/xcalar/scripts/xcasup.sh)
}

aws_s3() {
    (
    cmd="$1"
    shift
    eval_creds
    set_keys
    aws s3 $cmd --region us-west-2 "$PREFIX".tar.gz s3://${ASUP_BUCKET}/"$PREFIX".tar.gz
    )
}


upload() {
    DT=$(date +%s)
    DIR=$(mktemp -d -t xcasup2s3.XXXXXX)
    cd $DIR

    eval $(ec2-tags -s -i | tee tags.txt)

    PREFIX="uploads/saas/${AWS_CLOUDFORMATION_STACK_NAME}/$(date -d @$DT +%Y/%m/%d)/$(date -d @$DT +%Y%m%d_%H%M%S)-${AWS_AUTOSCALING_GROUPNAME}-${NODE_ID}-${INSTANCE_ID}"
    mkdir -p "$PREFIX"
    sudo -n cloud-init collect-logs -u
    mv tags.txt "$PREFIX"/tags.txt
    systemd-analyze plot > "$PREFIX"/systemd-analyze.svg
    systemd-analyze critical-chain > "$PREFIX"/critical-chain.txt
    systemd-analyze blame > "$PREFIX"/blame.txt
    tar zxvf cloud-init*.tar.gz -C "$PREFIX"
    tar czvf "$PREFIX".tar.gz "$PREFIX"/
    set_keys
    aws_s3 cp "$PREFIX".tar.gz s3://${ASUP_BUCKET}/"$PREFIX".tar.gz
    mv "$PREFIX".tar.gz /var/log/
}

upload

exit $?

