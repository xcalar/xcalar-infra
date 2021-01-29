# edit these

json_param (){
    local v=
    if v="$(jq -r "${PARAMS}${1}" "$PARAMETERS")" && [ "$v" != null ]; then
        echo $v
        return 0
    fi
    return 1
}

PARAMETERS="${PARAMETERS:-parameters.main.json}"
if [ -e $PARAMETERS ]; then
    PARAMS=''
    if [ "$(json_param .parameters)" != null ]; then
        PARAMS=".parameters"
    fi
    if [ -z "$LOCATION" ]; then
        LOCATION="$(json_param .location.value)"
        echo >&2 "WARNING: Using location from $PARAMETERS: LOCATION=$LOCATION"
    fi
    if [ -z  "$CLUSTER" ]; then
        CLUSTER="$(json_param .appName.value)"
        echo >&2 "WARNING: Using appName from $PARAMETERS: CLUSTER=$CLUSTER"
    fi
fi

while getopts "g:n:l:" opt; do
    case "$opt" in
        g) GROUP="$OPTARG";;
        n) DEPLOY="$OPTARG";;
        l) LOCATION="$OPTARG";;
        --) break;;
        -*) echo >&2 "ERROR: Unknown argument $opt. If this argument was intended for 'az' Please end your argument list with --"; exit 2;;
    esac
done
shift $((OPTIND-1))

test -n  "$GROUP" || GROUP="${1:? Need to specify a group}"

# this one is static per version of the mainTemplate.json
GROUP_INFO=($(az group show -g $GROUP -otsv))
if [ $? -ne 0 ] || [ -z "${GROUP_INFO}" ]; then
    az group create --name $GROUP --location $LOCATION || exit 1
    # this one is static per version of the mainTemplate.json
    GROUP_INFO=($(az group show -g $GROUP -otsv))
    if [ $? -ne 0 ] || [ -z "${GROUP_INFO}" ]; then
        echo  >&2 "ERROR: Couldn't create or find info for group"
        exit 1
    fi
fi

if [ -z "$BASE_URL" ]; then
    if [ "${BASE_URL-x}" = x ]; then
        BASE_URL=https://s3-us-west-2.amazonaws.com/xcrepo/temp/bysha1/3eba12e6
    else
        BASE_URL="$(dirname $(./upload.sh -u xdp-standard-package.zip))"
    fi
fi


DEPLOY_URL="https://portal.azure.com/#resource/${GROUP_INFO[0]}/overview"
NOW="$(date +%s)"
DEPLOY="${DEPLOY:-${GROUP}-${NOW}-deploy}"
if [ -n "$DISPLAY" ]; then
    [[ "$OSTYPE" =~ darwin ]]  && open "$DEPLOY_URL" || google-chrome "$DEPLOY_URL"
fi
echo "DeploymentURL: $DEPLOY_URL"

echo
echo "You'll be able to ssh into your instance long before this next step completes."
echo
(set -x
az deployment group create --name "${DEPLOY}" \
                           --resource-group "${GROUP}" \
                           --template-uri "$BASE_URL/mainTemplate.json" \
                           --parameters @${PARAMETERS} \
                           --parameters _artifactsLocation="$BASE_URL" \
                           ${CLUSTER:---parameters appName=$CLUSTER} --parameters location=$LOCATION "$@"
)
echo You can ssh into your first node via "ssh userfromjson@instance-vm0-from-below"
az vm list-ip-addresses -g $GROUP -otable
