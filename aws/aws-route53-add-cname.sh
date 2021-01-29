#!/bin/bash

export AWS_HOSTED_ZONE_ID="Z2S03H582J2UUD" # for lego
export AWS_DEFAULT_REGION=us-west-2
SUBDOMAIN="xcalar.io"

while getopts "a:b:c:d:e:f:g:i:n:l:u:r:p:s:t:v:w:x:y:z:" optarg; do
    case "$optarg" in
        a) SUBDOMAIN="$OPTARG";;
        b) export AWS_HOSTED_ZONE_ID="$OPTARG";;
        c) CLUSTER="$OPTARG";;
        d) DNSLABELPREFIX="$OPTARG";;
        e) export AWS_ACCESS_KEY_ID="$OPTARG";;
        f) export AWS_SECRET_ACCESS_KEY="$OPTARG";;
        g) PASSWORD="$OPTARG";;
        i) INDEX="$OPTARG";;
        n) COUNT="$OPTARG";;
        l) LICENSE="$OPTARG";;
        u) INSTALLER_URL="$OPTARG";;
        r) CASERVER="$OPTARG";;
        p) PEM_URL="$OPTARG";;
        t) CONTAINER="$OPTARG";;
        s) NFSMOUNT="$OPTARG";;
        v) ADMIN_EMAIL="$OPTARG";;
        w) ADMIN_USERNAME="$OPTARG";;
        x) ADMIN_PASSWORD="$OPTARG";;
        y) export AZURE_STORAGE_ACCOUNT="$OPTARG";;
        z) export AZURE_STORAGE_ACCESS_KEY="$OPTARG"; export AZURE_STORAGE_KEY="$OPTARG";;
        --) break;;
        *) echo >&2 "Unknown option $optarg $OPTARG";; # exit 2;;
    esac
done
shift $((OPTIND-1))


download_cert () {
    local gpgfile="$(basename "$1")" try=0
    local tarfile="$(basename "$gpgfile" .gpg)"
    local pemfile= keyfile=
    aws s3 cp "$1" "$gpgfile" >&2 && \
    while [ $try -lt 10 ]; do
        if [[ $gpgfile =~ \.gpg$ ]]; then
            echo "$2"| gpg --passphrase-fd 0 --batch --quiet --yes --no-tty -d "$gpgfile" > "$tarfile"
        fi && \
        pemfile="$(tar tf "$tarfile" | grep -E '\.(pem|crt)' | head -1)" && \
        keyfile="$(tar tf "$tarfile" | grep -E '\.key' | head -1)" && \
        tar zxf "$tarfile" && \
        echo "${PWD}/${pemfile}" && \
        return 0
        try=$((try+1))
        sleep 5
    done
    return 1
}

lego_register_domain() {
    if ! test -e /usr/local/bin/lego; then
        safe_curl -L https://github.com/xenolf/lego/releases/download/v0.4.0/lego_linux_amd64.tar.xz | \
            tar Jxvf - --no-same-owner lego_linux_amd64
        mv lego_linux_amd64 /usr/local/bin/lego
        chmod +x /usr/local/bin/lego
        setcap cap_net_bind_service=+ep /usr/local/bin/lego
    fi
    local caserver="$1" domains=() domain=
    shift
    for domain in "$@"; do
        domains+=(-d $domain)
    done
    if ! lego --server "$caserver" "${domains[@]}" --dns route53 --accept-tos --email "${ADMIN_EMAIL}" run; then
        echo >&2 "Failed to acquire certificate"
        return 1
    fi
    cp ".lego/certificates/${1}.crt" /etc/xcalar/ && cp ".lego/certificates/${1}.key" /etc/xcalar/ && \
        return 0
    return 1
}

pem_san_list () {
    openssl x509 -noout -text -in "$1" | grep 'DNS:' | sed -r 's/ DNS://g; s/^[\t ]+//g; s/,/\n/g'
}

aws_route53_list () {
    aws route53 list-resource-record-sets --hosted-zone-id "$AWS_HOSTED_ZONE_ID" --query 'ResourceRecordSets[].Name' --output text | tr '\t' '\n' | grep '\.'${SUBDOMAIN} | sort
}

dns_find_slot () {
    aws_route53_list > zone_records.txt
    pem_san_list "$1" > pem_san.txt
    if grep -q '\*\.'${SUBDOMAIN} pem_san.txt; then
        echo "${DNSLABELPREFIX}.${SUBDOMAIN}"
        return 0
    fi
    comm -13 zone_records.txt pem_san.txt > allowed.txt
    local precert="$(comm -13 zone_records.txt pem_san.txt | head -1 | tee -a dnsname.txt)"
    if [ -z "$precert" ]; then
        return 1
    fi
    echo "$precert"
}

# Create a resource record that points xd-standard-amit-0.westus2.cloud.azure.com -> yourprefix.azure.xcalar.cloud
aws_route53_record () {
    local CNAME="$1" NAME="$2" rrtmp="$(mktemp /tmp/rrsetXXXXXX.json)" change_id=
    cat > $rrtmp <<EOF
    { "HostedZoneId": "$AWS_HOSTED_ZONE_ID", "ChangeBatch": { "Comment": "Adding $CNAME",
      "Changes": [ {
        "Action": "UPSERT",
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


aws_route53_record "$@"
