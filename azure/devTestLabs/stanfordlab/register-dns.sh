#!/bin/bash

# Generate table via:
# openssl x509 -noout -text -in ../../xdp-standard/certs/xcalar-stanfordlab-100.xcalar.io.pem | sed -r 's/^\s+//g' | grep '^DNS:' | sed -e 's/DNS://g' | tr -d ',' | tr ' ' '\n' | sort -V
export AWS_HOSTED_ZONE_ID="Z2S03H582J2UUD" # for lego
export AWS_DEFAULT_REGION=us-west-2
SUBDOMAIN="xcalar.io"

PREFIX=xcalar-stanfordlab
DOMAIN=xcalar.io

DSTDOM=westus2.cloudapp.azure.com
DPREFIX=xcalar-stanford
DSTSTART=0
DSTDIGIT=2
SRCDIGIT=2
COUNT=90

ADMIN=0
DEV=1
INT=2
PLAIN=3

srcformat () {
    printf "${PREFIX}-1%0${SRCDIGIT}d.${DOMAIN}" $1
}

dstformat () {
    printf "${DPREFIX}-1%0${DSTDIGIT}d.${DSTDOM}" $1
}

generate_name_pairs() {
    for ii in {0..4}; do
        echo -e "$(dstformat $ii)\t\t${PREFIX}-${ii}.${DOMAIN}."
    done

    echo -e "$(dstformat $PLAIN)\t\t${PREFIX}.${DOMAIN}."
    echo -e "$(dstformat $DEV)\t\t${PREFIX}-dev.${DOMAIN}."
    echo -e "$(dstformat $INT)\t\t${PREFIX}-int.${DOMAIN}."
    echo -e "$(dstformat $ADMIN)\t\t${PREFIX}-admin.${DOMAIN}."
}


# Create a resource record that points xd-standard-amit-0.westus2.cloud.azure.com -> yourprefix.azure.xcalar.cloud
aws_route53_record () {
    local CNAME="$1" NAME="$2" ACTION="${3:-UPSERT}" rrtmp="$(mktemp /tmp/rrsetXXXXXX.json)" change_id=
    cat > $rrtmp <<EOF
    { "HostedZoneId": "$AWS_HOSTED_ZONE_ID", "ChangeBatch": { "Comment": "Adding $CNAME",
      "Changes": [ {
        "Action": "$ACTION",
          "ResourceRecordSet": { "Name": "$NAME", "Type": "CNAME", "TTL": 60,
            "ResourceRecords": [ { "Value": "$CNAME" } ] } } ] } }
EOF
    change_id="$(set -o pipefail; aws route53 change-resource-record-sets --cli-input-json file://${rrtmp} | jq -r '.ChangeInfo.Id' | cut -d'/' -f3)"
    if [ $? -eq 0 ] && [ "$change_id" != "" ]; then
        echo "$change_id"
        return 0
    fi
    return 1
}


if [ "$1" == "--register" ]; then
    while read CNAME NAME; do aws_route53_record $CNAME $NAME UPSERT; done
elif [ "$1" == "--deregister" ]; then
    while read CNAME NAME; do aws_route53_record $CNAME $NAME DELETE; done
elif [ "$1" == "--keyscan" ]; then
    sed -e 's/\.$//g' | head -10 | xargs -n 2 -P 1 -I{} bash -c "set -x; ssh-keyscan {} | tee -a $HOME/.ssh/known_hosts"
else
    generate_name_pairs
    for ii in {0..90}; do
        echo -e "$(dstformat $ii)\t\t$(srcformat $ii)."
    done
fi


