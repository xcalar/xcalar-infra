#!/bin/bash
# Instance meta-data service v2
IMDSV2=latest
ec2_mds() {
    if [ -z "$IMDSV2_TOKEN" ]; then
        declare -g IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/$IMDSV2/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    fi
    curl -fsSL -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/$IMDSV2/${1#/}" && echo
}
