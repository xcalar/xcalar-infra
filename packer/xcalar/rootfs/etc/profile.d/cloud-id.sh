#!/bin/bash

cloud_id() {
    local dmi_id='/sys/class/dmi/id/sys_vendor'
    local vendor cloud

    cloud=none
    if [ -n "$container" ]; then
        cloud="$container"
    elif [ -e /run/systemd/container ]; then
        cloud=$(cat /run/systemd/container)
    elif [ -e "$dmi_id" ]; then
        read -r vendor <"$dmi_id"
        case "$vendor" in
            Microsoft\ Corporation) cloud=azure ;;
            Amazon\ EC2) cloud=aws ;;
            Google) cloud=gcp ;;
            VMWare*) cloud=vmware ;;
            oVirt*) cloud=ovirt ;;
        esac
        echo "$cloud"
        return 0
    fi
    echo "$cloud"
    return 1
}

az_mds() {
    if command -v jq >/dev/null; then
        curl --silent -H 'Metadata:True' "http://169.254.169.254/metadata/${1:-instance}?api-version=2020-06-01&format=json" | jq .
    else
        curl --silent -H 'Metadata:True' "http://169.254.169.254/metadata/${1:-instance}?api-version=2020-06-01&format=json"
    fi
}

ec2_mds() {
    IMDSV2=latest
    if [ -z "$IMDSV2_TOKEN" ]; then
        declare -g IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/$IMDSV2/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    fi
    curl --silent -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/$IMDSV2/${1#/}" && echo
}

gcp_mds() {
    # NOTE: should start with project/ or instancee/
    curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/"$1"
}
