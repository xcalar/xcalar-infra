#!/bin/bash
#
# Create an AWS Cloudformation Stack
#
# Usage:
#  ./aws-cluster.sh -h
#
# Usage (legacy, will be deprecated):
#  ./aws-cluster.sh [node-count (default:2)] [instance-type (default: i3.4xlarge)]
#
# RECOMMENDED INSTANCE TYPES for DEMOS
#
# i3.4xlarge = 16 vCPUs x 122GiB x 3800GiB SSD = $1.248/hr
# i3.8xlarge = 32 vCPUs x 244GiB x 7600GiB SSD = $2.496/hr
# r3.8xlarge = 32 vCPUs x 244GB x 600GB SSD = $2.660/hr
#
# Compare EC2 instance types for CPU, RAM, SSD with this calculator:
# http://www.ec2instances.info/?min_memory=60&min_vcpus=32&min_storage=1&region=us-west-2)
#
DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

if ! command -v cfn-flip >/dev/null; then
    echo >&2 "You need to have cfn-flip installed"
    echo >&2 "  pip install -U cfn-flip"
    exit 1
fi

. aws-sh-lib

declare -a PARAMS

NOW=$(date +%Y%m%d%H%M)
DEFAULT_TEMPLATE="${XLRINFRADIR}/aws/cfn/XCE-CloudFormationMultiNodeInternal.yaml"
DEFAULT_SPOT_TEMPLATE="$(dirname $DEFAULT_TEMPLATE)/$(basename $DEFAULT_TEMPLATE .yaml)Spot.yaml"
BUCKET=xcrepo
COUNT=3
NODEID=0
BOOTSTRAP= #aws-cfn-bootstrap.sh
SUBNET=subnet-b9ed4ee0  # subnet-4e6e2d15
ROLE="xcalar_field"
KEY_NAME=xcalar-us-west-2
#BOOTSTRAP_URL="${BOOTSTRAP_URL:-http://repo.xcalar.net/scripts/aws-asg-bootstrap-field-new.sh}"
#INSTALLER="${INSTALLER:-s3://xcrepo/builds/prod/xcalar-1.3.2-1758-installer}"
LOGNAME="${LOGNAME:-`id -un`}"
STACK_NAME="$LOGNAME-cluster-$NOW"
#BootstrapUrl	http://repo.xcalar.net/scripts/aws-asg-bootstrap-field.sh
#InstallerUrl    "$(aws s3 presign s3://xcrepo/builds/c94df876-5ab9a93c/prod/xcalar-1.2.2-1236-installer)"
IMAGE=$(aws_latest_official_image "EL7")
SPOT=0
LICENSE="license.txt"

usage () {
    cat << EOF
usage: $0 [-a image-id (default: $IMAGE)] [-i installer (default: $INSTALLER)] [-u installer-url (default: $INSTALLER_URL)]
          [-t instance-type (default: $INSTANCE_TYPE)] [-c count (default: $COUNT)] [-n stack-name (default: $STACK_NAME)]
          [-b bootstrap (default: $BOOTSTRAP)] [-f template (default: $DEFAULT_TEMPLATE) [-e subnet-id (default: $SUBNET)]
          [-s spot-price multiplier (0 to disable, default: $SPOT)] [-l "licensefile-or-key"]

EOF
    exit 1
}

upload_bysha1 () {
    local sha1= bn= key= s3path=
    sha1="$(shasum "$1" | cut -d' ' -f1)"
    bn="$(basename "$1")"
    key="bysha1/${sha1}/${bn}"
    s3path="s3://${BUCKET}/${key}"
    if ! aws s3 ls "$s3path" >/dev/null 2>&1; then
        aws s3 cp "$1" "$s3path" >/dev/null || return 1
    fi
    aws s3 presign --expires-in 3600 "$s3path"
}

check_url () {
    local code=
    if code="$(curl -fsSL -r 0-0 -w '%{http_code}\n' -o /dev/null "$1")"; then
        if [[ $code =~ ^[23] ]]; then
            return 0
        fi
    fi
    return 1
}

parameter_keys() {
  if [[ "$1" =~ ^http ]]; then
    if echo "$1" | grep -q '.yaml$'; then
      curl -L "$1" | cfn-flip | jq -r '.Parameters|keys[]'
    else
      curl -L "$1" | jq -r '.Parameters|keys[]'
    fi
  else
    if echo "$1" | grep -q '.yaml$'; then
      cfn-flip < "${1#file://}" | jq -r '.Parameters|keys[]'
    else
      jq -r '.Parameters|keys[]' < "${1#file://}"
    fi
  fi
}

template_default() {
    cfn-flip "$TEMPLATE" | jq -r ".Parameters.$1.Default"
}

is_param() {
    test -z "$VALID_PARAMS" && VALID_PARAMS=$(parameter_keys "$TEMPLATE")
    grep -q "$1" <<< "$VALID_PARAMS"
}

while getopts "ha:i:u:t:c:n:s:b:f:r:e:l:" opt "$@"; do
    case "$opt" in
        h) usage;;
        a) IMAGE="$OPTARG";;
        i) INSTALLER="$OPTARG";;
        u) INSTALLER_URL="$OPTARG";;
        t) INSTANCE_TYPE="$OPTARG";;
        c) COUNT="$OPTARG";;
        n) STACK_NAME="$OPTARG";;
        e) SUBNET="$OPTARG";;
        s) SPOT="$OPTARG";;
        b) BOOTSTRAP="$OPTARG";;
        f) TEMPLATE="$OPTARG";;
        r) ROLE="$OPTARG";;
        l) LICENSE="$OPTARG";;
        --) break;;
        *) echo >&2 "Unknown option $opt"; usage;;
    esac
done


if [ -z "$TEMPLATE" ]; then
    if [ "$SPOT" = 0 ]; then
        TEMPLATE="$DEFAULT_TEMPLATE"
    else
        TEMPLATE="$DEFAULT_SPOT_TEMPLATE"
    fi
fi

shift $((OPTIND-1))

if [ -n "$INSTALLER" ] && [ -z "$INSTALLER_URL" ]; then
    if [ "$INSTALLER" = "none" ]; then
        INSTALLER_URL="http://none"
    elif [[ "$INSTALLER" =~ ^s3:// ]]; then
        if ! INSTALLER_URL="$(aws s3 presign "$INSTALLER")"; then
            echo >&2 "Unable to sign the s3 uri: $INSTALLER"
        fi
    elif [[ "$INSTALLER" =~ ^gs:// ]]; then
        INSTALLER_URL="http://${INSTALLER#gs://}"
    elif [[ "$INSTALLER" =~ ^http[s]?:// ]]; then
        INSTALLER_URL="$INSTALLER"
    elif test -e "$INSTALLER"; then
        if ! INSTALLER_URL="$($XLRINFRADIR/bin/installer-url.sh -d s3 "$INSTALLER")"; then
            echo >&2 "Failed to upload or generate a url for $INSTALLER"
            exit 1
        fi
    fi
fi

if [ -n "$BOOTSTRAP" ]; then
    if ! BOOTSTRAP_URL="$(upload_bysha1 ${BOOTSTRAP})"; then
        echo >&2 "Failed to upload $BOOTSTRAP"
    fi
fi

if [ -z "$INSTALLER_URL" ]; then
    INSTALLER_URL="$(template_default InstallerUrl)"
fi

for URL in "$INSTALLER_URL"; do
    if test -z "$URL" || ! check_url "$URL"; then
        echo >&2 "Failed to access the installer url: $URL"
        exit 1
    fi
done

if test -e "$LICENSE"; then
  LICENSE="$(cat $LICENSE)" || { echo >&2 "Failed to read license file"; exit 1; }
fi

VALID_PARAMS=$(parameter_keys $TEMPLATE)


PARMS=(\
#InstallerUrl   "${INSTALLER_URL}"
InstanceCount	"${COUNT}"
KeyName	        "${KEY_NAME}"
Subnet	        $SUBNET
AdminUsername   xdpadmin
AdminPassword   Welcome1
AdminEmail      "$(git config user.email || echo test@xcalar.com)"
LicenseKey      "$LICENSE"
VpcId	        vpc-22f26347)

test -n "$BOOTSTRAP_URL" && PARAMS+=(BootstrapUrl "${BOOTSTRAP_URL}")
test -n "$IMAGE" && PARAMS+=(ImageId $IMAGE)
test -n "$INSTANCE_TYPE" && PARAMS+=(InstanceType "$INSTANCE_TYPE")

if grep -q SpotPrice <<< "$VALID_PARAMS" && [ "$SPOT" != 0 ]; then
    ZONE=$(aws_subnet_to_zone $SUBNET)
    SPOTPRICE=$(aws_spot_price $INSTANCE_TYPE $ZONE | head -1 | awk '{print $(NF-1)}')
    BIDPRICE="$(echo "$SPOTPRICE * $SPOT" | bc)"
    BIDPRICE="$(printf '%1.4f' $BIDPRICE)"
    PARMS+=(SpotPrice $BIDPRICE)
    echo >&2 "$INSTANCE_TYPE: SpotPrice: $SPOTPRICE , MaxBid: $BIDPRICE, Zone: $ZONE"
fi

case "$TEMPLATE" in
    http://*) ;;
    https://*) ;;
    file://*) ;;
    *)
    if test -f "$TEMPLATE"; then
        TEMPLATE="file://${TEMPLATE}"
    else
        echo >&2 "WARNING: Couldn't parse $TEMPLATE"
        echo >&2 "WARNING: This Cfn stack could fail!!"
    fi
    ;;
esac

ARGS=()
for ii in $(seq 0 2 $(( ${#PARMS[@]} - 1)) ); do
    k=$(( $ii + 0 ))
    v=$(( $ii + 1 ))
    if is_param "${PARMS[$k]}"; then
      ARGS+=(ParameterKey=${PARMS[$k]},ParameterValue=\"${PARMS[$v]}\")
      echo >&2 "Parameter: ${PARMS[$k]}=${PARMS[$v]}"
    else
      echo >&2 "Skipping Parameter: ${PARMS[$k]}"
    fi
done

set -e
aws cloudformation validate-template --template-body ${TEMPLATE} >/dev/null
aws cloudformation create-stack \
        --stack-name ${STACK_NAME} \
        --template-body ${TEMPLATE} \
        --timeout-in-minutes 30 \
        --on-failure DELETE \
        --capabilities CAPABILITY_IAM \
        --tags \
            Key=Name,Value=${STACK_NAME} \
            Key=Owner,Value=${LOGNAME} \
            Key=Role,Value=${ROLE} \
        --parameters "${ARGS[@]}"
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME}

