#!/bin/bash
set -e

. infra-sh-lib

TEMPLATE=${TEMPLATE:-mainTemplate.json}

LOCATION=westus2
if ! NAME="$(git config user.name)"; then
    say "Must configure your git user.name: git config --global user.name"
    die 1
fi
if ! EMAIL="$(git config user.email)"; then
    say "Must configure your git email: git config --global user.email"
    die 1
fi

usage() {
    echo >&2 "Usage: $0 [options] where options are:"
    echo >&2 "-t|--template        template.json              Use this template for deployment (default: from env or \$TEMPLATE=$TEMPLATE)"
    echo >&2 "--parameters-file    parameters.template.json   Use this json for parameters if it exists (default: parameters.$TEMPLATE)"
    echo >&2 '-g|--resource-group  resourceGroup    Use this resourceGroup to deploy into (default: from env $GROUP if set else generated based on USER)'
    echo >&2 "-l|--location        location         Use this location (default: $LOCATION or from env \$LOCATION if set)"
    echo >&2 "--storageAccount     storageAccount   Use this storage account (default: "

    PARAMETER_KEYS=$(jq <$TEMPLATE -r '.parameters|keys|@tsv')
    for param in ${PARAMETER_KEYS}; do
        DESC="$(jq <$TEMPLATE -r '.parameters.'$param'.metadata.description')"
        DEFAULT="$($TEMPLATE jq -r '.parameters.'$param'.defaultValue')"
        echo "--$param=value        $DESC (default: $DEFAULT, taken from $TEMPLATE)"
    done
    exit 1
}

parse_args() {
    if ! test -r "$TEMPLATE"; then
        die "Unable to read template $TEMPLATE"
    fi
}

TMPDIR="${TMPDIR:-/tmp}/$(id -un)/upload"
mkdir -p $TMPDIR

BUCKET=xcrepo
KEYBASE=temp/bysha1
PARAMETERS="${PARAMETERS:-parameters.main.json}"

test $# -eq 0 && set -- xdp-standard-package.zip deploy

if ! test -e "$XLRINFRADIR/azure/azure-sh-lib"; then
    echo >&2 "Need to set XLRINFRADIR"
    exit 1
fi

. $XLRINFRADIR/azure/azure-sh-lib

sha1url() {
    local bn="$(basename $1)"
    echo "https://s3-us-west-2.amazonaws.com/${BUCKET}/${KEYBASE}/$(get_sha1 $1)/${bn}"
}

# Get $1 (default: 4) random chars from the set of a-z 0-9
dns_rand() {
    echo {a..z}{0..9} | tr ' ' '\n' | shuf | tr -d '\n' | cut -c1-${1:-4}
}

artifacts() {
    echo "https://${AZ_PUBLIC_ACCOUNT}.blob.core.windows.net/${AZ_PUBLIC_CONTAINER}/$1"
}

rawurlencode() {
    (
        set +x
        local string="${1}"
        local strlen=${#string}
        local encoded=""
        local pos c o

        for ((pos = 0; pos < strlen; pos++)); do
            c=${string:pos:1}
            case "$c" in
                [-_.~a-zA-Z0-9]) o="${c}" ;;
                *) printf -v o '%%%02x' "'$c" ;;
            esac
            encoded+="${o}"
        done
        echo "${encoded}"
    )
}

upload() {
    local src="$1"
    local dst="${2:-$src}"
    # az_blob_upload_public "$src" "${KEY}/${dst}"
    if [ "$USE_S3" = 1 ]; then
        aws s3 cp --quiet --acl public-read --metadata-directive REPLACE --cache-control 'no-cache, no-store, must-revalidate, max-age=0, no-transform' $src "s3://${BUCKET}/${KEY}/${dst}" \
            && local url="https://s3-us-west-2.amazonaws.com/${BUCKET}/${KEY}/${dst}"
        echo "$url"
    else
        az_blob_upload_public "$src" "${KEY}/${dst}"
    fi
}

check() {
    local rc=0
    while [ $# -gt 0 ]; do
        if echo "$1" | grep -q '\.json$'; then
            jq -r '.' <"$1" >/dev/null
        elif echo "$1" | grep -q '\.sh$' || test -x "$1"; then
            bash -n "$1"
        else
            shift
            continue
        fi
        rc=$?
        if [ $rc -ne 0 ]; then
            echo >&2 "ERROR: $1 failed validation"
            exit 1
        fi
        shift
    done
}
test -e key.txt && KEY=$(cat key.txt)

while getopts "nu:k:" cmd; do
    case "$cmd" in
        n) NO_WAIT=1 ;;
        u)
            UPLOAD="$OPTARG"
            sha1url "$UPLOAD"
            exit 0
            ;;
        k) KEY="$OPTARG" ;;
        --) break ;;
        -*) echo >&2 "Unknown $cmd ..." ;;
    esac
done
shift $((OPTIND - 1))

XDP=xdp-standard-package.zip

if ! test -n "$1"; then
    set -- "$XDP" deploy
fi

if [ "$1" = $XDP ]; then
    rm -f xdp-standard-package.zip payload.tar.gz
    make xdp-standard-package.zip
fi

BN="$(basename $1)"
if [ "$1" = "$XDP" ]; then
    if ! check bootstrap.sh createUiDefinition.json $TEMPLATE payload/*; then
        echo >&2 "ERROR: Validation failed"
        exit 1
    fi
    shasum bootstrap.sh createUiDefinition.json $TEMPLATE payload/* >$TMPDIR/allsha1.txt
    SHA1="$(get_sha1 $TMPDIR/allsha1.txt)"
else
    SHA1="$(get_sha1 $1)"
fi
if [ -z "$KEY" ]; then
    KEY="$KEYBASE/$SHA1"
fi

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        *.zip)
            upload "$cmd"
            rm -rf "${TMPDIR}/${KEY}"
            mkdir -p ${TMPDIR}/${KEY}
            zip=$(readlink -f $cmd)
            cd ${TMPDIR}/${KEY}
            unzip -q -o $zip
            artifactsLoc="$(artifacts $KEY)"
            #json_set '.parameters._artifactsLocation.defaultValue="'"${artifactsLoc}"'"' $TEMPLATE || \
            #    die "Failed to set artifactsLoc in $TEMPLATE"
            bootstrapUrl="$(upload bootstrap.sh)"
            templateUrl="$(upload $TEMPLATE)"
            createUiUrl="$(upload createUiDefinition.json)"
            payloadUrl="$(upload payload.tar.gz)"
            cd - >/dev/null
            urlcode="$(rawurlencode "{\"initialData\":{},\"providerConfig\":{\"createUiDefinition\":\"$createUiUrl\"}}")"
            URL="https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/$urlcode"
            echo "<br/><a href=\"$URL\">[[Preview #${COUNT}]]</a>" >>azure.html

            UUID=$(uuidgen | cut -d- -f1)
            if ! [ "$NO_WAIT" = 1 ]; then
                google-chrome "$URL"
            fi
            echo
            echo "TemplateURL: $templateUrl"
            echo
            ;;
        deploy)
            COUNT="$(cat count.txt 2>/dev/null || echo 1)"
            GROUP=${GROUP:-${USER}-${COUNT}-rg}
            VMNAME=${GROUP%-rg}-vm
            CLUSTER=${GROUP%-rg}-cluster
            DEPLOY=${GROUP%-rg}-deploy-$(date +%Y%m%d%H%M)
            if [ -z "$LOCATION" ] && ! LOCATION="$(json_param .location.value)"; then
                LOCATION=westus2
            fi

            if [ "$(az group exists --name $GROUP --output tsv)" != true ]; then
                az group create -l "${LOCATION}" --name "$GROUP" --tags "email:$(git config user.email)" || exit 1
            fi
            echo "GROUP=$GROUP" >>local.mk
            test -e $PARAMETERS && echo "=== here's your original $PARAMETERS ===" && cat $PARAMETERS
            echo "====== save your params to $PARAMETERS and press any key ====="
            test "$NO_WAIT" = 1 || read
            EXTRA_ARGS=()
            if ! json_param ".domainNameLabel.value" >/dev/null; then
                if ! host "$(az_dns $GROUP 2>/dev/null)"; then
                    EXTRA_ARGS+=(--parameters domainNameLabel="${CLUSTER}")
                else
                    EXTRA_ARGS+=(--parameters domainNameLabel="${CLUSTER}-$(dns_rand)")
                fi
            fi
            if ! json_param ".publicIpAddressName.value" >/dev/null; then
                EXTRA_ARGS+=(--parameters publicIpAddressName="${CLUSTER}-pip")
            fi
            if INSTALLER_URL="$(json_param ".installerUrl.value")"; then
                if ! check_url "$INSTALLER_URL"; then
                    die "Provided installer url '$INSTALLER_URL' isn't reachable"
                fi
            fi
            (
                debug az deployment group validate --template-uri "${templateUrl}" --parameters @$PARAMETERS --parameters _artifactsLocation="$artifactsLoc" --parameters _artifactsLocationSasToken='' \
                    --parameters "location=${LOCATION}" --parameters appName=${CLUSTER} "${EXTRA_ARGS[@]}" -g "${GROUP}" -ojson >$TMPDIR/error.json
                code="$(jq -r .error.code <$TMPDIR/error.json)"
                if [ $? -ne 0 ] || [ "$code" != "null" ]; then
                    echo >&2 "FAILED: $code"
                    jq -r . <$TMPDIR/error.json
                    exit 1
                fi

                debug az deployment group create -g "${GROUP}" --name "${DEPLOY}" --no-wait -ojson --template-uri "${templateUrl}" --parameters @$PARAMETERS --parameters _artifactsLocation="$artifactsLoc" _artifactsLocationSasToken='' \
                    "location=${LOCATION}" appName=${CLUSTER} "${EXTRA_ARGS[@]}" >$TMPDIR/error.json
                debug az deployment group wait --exists -g "$GROUP" --name "$DEPLOY"
                google-chrome "$(az_rg_deployment_url $GROUP $DEPLOY)"
            )
            echo $((COUNT + 1)) >count.txt
            az deployment group wait --created -g $GROUP --name $DEPLOY
            DNS=$(az_rg_dns $GROUP)
            echo "DNS: $DNS"
            ssh $DNS
            ;;
    esac
done
