#!/bin/bash

ACTION="${ACTION:-UPSERT}"
TTL="${TTL:-60}"
TYPE="${TYPE:-CNAME}"
ZONE_ID="${ZONE_ID:-ZGHV0FVJ28G7N}"
DOMAIN="${DOMAIN:-3wpoc.xcalar.com}"

aws_meta() {
    curl --fail --silent http://169.254.169.254/2018-09-24/meta-data/$1
}

aws_tags() {
    TMP2=$(mktemp -t tags-XXXXXX.env)
    INSTANCE_ID=$(aws_meta instance-id)
    aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[].Instances[].Tags[]' --output text \
        | while read TAG VALUE; do
            if [ -z "$TAG" ]; then
                continue
            fi
            CLEANTAG="$(echo $TAG | tr 'a-z' 'A-Z' | tr ':' '_' | tr '-' '_')"
            echo "${CLEANTAG}=${VALUE}"
        done | tee $TMP2 >/dev/null
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        cat $TMP2
        rm $TMP2
        return 0
    fi
    return 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --record)
            RECORD="$2"
            shift 2
            ;;
        --name)
            NAME="$2"
            shift 2
            ;;
        --zone-id)
            ZONE_ID="$2"
            shift 2
            ;;
        --ttl)
            TTL="$2"
            shift 2
            ;;
        --fqdn)
            FQDN="$2"
            shift 2
            ;;
        --type)
            TYPE="$2"
            shift 2
            ;;
        -h | --help)
            echo >&2 "usage: $0 [--action UPSERT|INSERT|DELETE] [--type A|CNAME] [--fqdn FQDN] [--ttl TTL] [--domain DOMAIN]"
            echo >&2 "          [--name NAME] [--zone-id ZONE_ID] [--record RECORD]"
            echo >&2
            exit 1
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo >&2 "ERROR: Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$AWS_DEFAULT_REGION" ]; then
    AVZONE=$(aws_meta placement/availability-zone)
    export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"
fi

if [ -z "$RECORD" ]; then
    if [ "$TYPE" = A ]; then
        RECORD_TYPE=public-ipv4
    elif [ "$TYPE" = CNAME ]; then
        RECORD_TYPE=public-hostname
    else
        echo >&2 "ERROR: Unknown record type $TYPE"
        exit 1
    fi
    if ! RECORD="$(aws_meta $RECORD_TYPE)"; then
        echo >&2 "Failed to get public ip name. Please specify --record RECORD to point the NAME to"
        exit 1
    fi
fi

if [ -z "$FQDN" ]; then
    if [ -z "$NAME" ]; then
        eval $(aws_tags)
        if [ -n "$AWS_CLOUDFORMATION_STACK_NAME" ]; then
            NAME="$AWS_CLOUDFORMATION_STACK_NAME"
        fi
        if [ -z "$NAME" ]; then
            echo >&2 "Must specify --name or --fqdn"
            exit 1
        fi
    fi
    FQDN="${NAME}.${DOMAIN}"
fi

FQDN="$(echo $FQDN | tr 'A-Z' 'a-z' | tr '_' '-')"

TMP="$(mktemp -t r53-XXXXXX.json)"
cat >$TMP <<EOF
{
    "Comment": "Updated $(date +%Y%m%d%H%M%S)",
    "Changes": [
        {
            "Action": "${ACTION}",
            "ResourceRecordSet": {
                "Name": "${FQDN}",
                "Type": "${TYPE}",
                "TTL": ${TTL},
                "ResourceRecords": [
                    {
                        "Value": "${RECORD}"
                    }
                ]
            }
        }
    ]
}
EOF

if aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} \
    --change-batch file://${TMP} --query 'ChangeInfo.[Id,Status]' --output text; then
    rm $TMP
    exit 0
fi
echo >&2 "ERROR: Couldn't update Route53 Zone $ZONE_ID. Please see $TMP"
exit 1
