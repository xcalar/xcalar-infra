#!/bin/bash

INSTALLER="${1}"
COUNT="${2:-2}"
CLUSTER="${3:-`whoami`-xcalar}"
DIR="$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)"
IMAGE=${IMAGE:-ami-4185e621}
INSTANCE_TYPE=${INSTANCE_TYPE:-r3.2xlarge}
SUBNET_ID=${SUBNET_ID:-subnet-1a1c906d}
VPC_ID=${VPC_ID:-vpc-22f26347}
LOGNAME="jenkins-${CLUSTER}"
GCLOUD_SDK_URL="https://sdk.cloud.google.com"
UPLOADLOG=/tmp/$CLUSTER-manifest.log
CLOUDFORMATION_JSON="${CLOUDFORMATION_JSON:-file:///netstore/infra/aws/cfn/XCE-CloudFormation.json}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
export AWS_DEFAULT_AVAILABILITY_ZONE="${AWS_DEFAULT_AVAILABILITY_ZONE:-us-west-2a}"

say () {
    echo >&2 "$*"
}

die () {
    say "ERROR: $*"
    exit 1
}

if [ "$(uname -s)" = Darwin ]; then
    readlink_f () {
    (
        target="$1"

        cd "$(dirname $target)"
        target="$(basename $target)"

        # Iterate down a (possible) chain of symlinks
        while [ -L "$target" ]
        do
            target="$(readlink $target)"
            cd "$(dirname $target)"
            target="$(basename $target)"
         done

        echo "$(pwd -P)/$target"
        )
    }
else
    readlink_f () {
        readlink -f "$@"
    }
fi

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    die "usage: $0 <installer-url> <count (default: 3)> <cluster (default: `whoami`-xcalar)>"
fi

export PATH="$PATH:$HOME/google-cloud-sdk/bin"
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPDIR="${TMPDIR:-/tmp/$(id -u)}/$(basename ${BASH_SOURCE[0]} .sh)"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"
if [ "$1" == "--no-installer" ]; then
    INSTALLER="$TMPDIR/noop-installer"
    cat <<EOF > $INSTALLER
#!/bin/bash

echo "Done."

exit 0
EOF
    chmod 755 $INSTALLER
elif test -f "$1"; then
    INSTALLER="$(readlink_f ${1})"
elif [[ $1 =~ ^http[s]?:// ]]; then
    INSTALLER="$1"
else
    say "Can't find the installer $1"
    exit 1
fi

if ! command -v gcloud; then
    if test -e "$XLRDIR/bin/gcloud-sdk.sh"; then
        say "gcloud command not found, attemping to install via $XLRDIR/bin/gcloud-sdk.sh ..."
        bash "$XLRDIR/bin/gcloud-sdk.sh"

        if [ $? -ne 0 ]; then
            say "Failed to install gcloud sdk..."
            exit 1
        fi
    else
        echo "\$XLRDIR/bin/gcloud-sdk.sh not found, attempting to install from $GCLOUD_SDK_URL ..."
        export CLOUDSDK_CORE_DISABLE_PROMPTS=1
        set -o pipefail
        curl -sSL $GCLOUD_SDK_URL | bash -e
        if [ $? -ne 0 ]; then
            say "Failed to install gcloud sdk..."
            exit 1
        fi
        set +o pipefail
    fi
fi

INSTALLER_FNAME="$(basename $INSTALLER)"

if test -f "$INSTALLER"; then
    if [[ "$INSTALLER" =~ '/debug/' ]]; then
        INSTALLER_URL="repo.xcalar.net/builds/debug/$INSTALLER_FNAME"
    elif [[ "$INSTALLER" =~ '/prod/' ]]; then
        INSTALLER_URL="repo.xcalar.net/builds/prod/$INSTALLER_FNAME"
    else
        INSTALLER_URL="repo.xcalar.net/builds/$INSTALLER_FNAME"
    fi
    if ! gsutil ls gs://$INSTALLER_URL &>/dev/null; then
        say "Uploading $INSTALLER to gs://$INSTALLER_URL"
        until gsutil -m -o GSUtil:parallel_composite_upload_threshold=100M \
            cp -c -L "$UPLOADLOG" \
            "$INSTALLER" gs://$INSTALLER_URL; do
            sleep 1
        done
        mv $UPLOADLOG $(basename $UPLOADLOG .log)-finished.log
    else
        say "$INSTALLER_URL already exists. Not uploading."
    fi
    INSTALLER=http://${INSTALLER_URL}
fi

if [[ "${INSTALLER}" =~ ^http:// ]]; then
    if ! curl -Is "${INSTALLER}" | head -n 1 | grep -q '200 OK'; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
elif [[ "${INSTALLER}" =~ ^gs:// ]]; then
    if ! gsutil ls "${INSTALLER}" &>/dev/null; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
else
    say "WARNING: Unknown protocol ${INSTALLER}"
fi

if ! aws cloudformation validate-template --template-body ${CLOUDFORMATION_JSON}; then
    die "Cloudformation template validation failed"
fi

if ! aws cloudformation create-stack \
        --stack-name "${CLUSTER}" \
        --timeout-in-minutes 30 \
        --on-failure DELETE \
        --tags \
            Key=Name,Value="${CLUSTER}" \
            Key=Owner,Value="${LOGNAME}" \
            Key=Role,Value=xcalar-cluster \
        --template-body "${CLOUDFORMATION_JSON}" \
        --parameters \
            ParameterKey=InstallerUrl,ParameterValue="${INSTALLER}" \
            ParameterKey=InstanceCount,ParameterValue="${COUNT}" \
            ParameterKey=InstanceType,ParameterValue="${INSTANCE_TYPE}" \
            ParameterKey=Subnet,ParameterValue="${SUBNET_ID}" \
            ParameterKey=ImageId,ParameterValue="${IMAGE}" \
            ParameterKey=VpcId,ParameterValue="${VPC_ID}"; then

    die "Failed to create aws cloudformation stack"
fi

if ! aws cloudformation wait stack-create-complete --stack-name "${CLUSTER}" &> /dev/null; then
    res=$?
    if [ $res -ne 0 ]; then
        aws cloudformation delete-stack --stack-name "${CLUSTER}"
        die "Timed out waiting for ${CLUSTER} to create"
    fi
fi
