#!/bin/bash
export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}
GCLOUD_SDK_URL="https://sdk.cloud.google.com"

say() {
    echo >&2 "$*"
}

if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    say "usage: $0 <installer-url> <count (default: 3)> <cluster (default: $(whoami)-xcalar)>"
    exit 1
fi
export PATH="$PATH:$HOME/google-cloud-sdk/bin"
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPDIR=${TMPDIR:-/tmp}/gce-upgrade-$(id -u)/$$
mkdir -p "$TMPDIR"
INSTALLER="$(readlink -f ${1})"
INSTALLER_FNAME="$(basename $INSTALLER)"
COUNT="${2:-3}"
CLUSTER="${3:-$(whoami)-xcalar}"
UPLOADLOG=$TMPDIR/$CLUSTER-manifest.log
WHOAMI="$(whoami)"
EMAIL="$(git config user.email)"
INSTANCES=($(
    set -o braceexpand
    eval echo $CLUSTER-{1..$COUNT}
))

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
if test -f "$INSTALLER"; then
    INSTALLER_URL="repo.xcalar.net/builds/$INSTALLER_FNAME"
    if ! gsutil ls gs://$INSTALLER_URL &>/dev/null; then
        say "Uploading $INSTALLER to gs://$INSTALLER_URL"
        until gsutil -m -o GSUtil:parallel_composite_upload_threshold=100M \
            cp -c -L "$UPLOADLOG" \
            "$INSTALLER" gs://"$INSTALLER_URL"; do
            sleep 1
        done
        mv $UPLOADLOG $(basename $UPLOADLOG .log)-finished.log
    else
        say "$INSTALLER_URL already exists. Not uploading."
    fi
    INSTALLER=http://${INSTALLER_URL}
fi

if [[ ${INSTALLER} =~ ^http:// ]]; then
    if ! curl -Is "${INSTALLER}" | head -n 1 | grep -q '200 OK'; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
elif [[ ${INSTALLER} =~ ^gs:// ]]; then
    if ! gsutil ls "${INSTALLER}" &>/dev/null; then
        say "Unable to access ${INSTALLER}"
        exit 1
    fi
else
    say "WARNING: Unknown protocol ${INSTALLER}"
fi

PIDS=()
say "Shutting down xcalar on ${#INSTANCES[*]} instances: ${INSTANCES[*]} .."
for host in "${INSTANCES[@]}"; do
    gcloud compute ssh "$host" --command "sudo systemctl stop xcalar.service" </dev/null &
    PIDS+=($!)
done
ret=0
for pid in "${PIDS[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        ret=1
    fi
done
if [ $ret -eq 1 ]; then
    echo "service xcalar stop failed"
    exit $ret
fi
PIDS=()

say "Copying new installer to ${#INSTANCES[*]} instances: ${INSTANCES[*]} .."

for host in "${INSTANCES[@]}"; do
    gcloud compute ssh "$host" --command "curl -sSl $INSTALLER > xcalar-installer" </dev/null &
    PIDS+=($!)
done
ret=0
for pid in "${PIDS[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        ret=1
    fi
done
if [ $ret -eq 1 ]; then
    echo "installer download stop failed"
    exit $ret
fi
PIDS=()

say "Reinstalling on ${#INSTANCES[*]} instances: ${INSTANCES[*]} .."

for host in "${INSTANCES[@]}"; do
    gcloud compute ssh "$host" --command "sudo bash xcalar-installer && sudo systemctl start xcalar.service" </dev/null &
    PIDS+=($!)
done
ret=0
for pid in "${PIDS[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        ret=1
    fi
done
if [ $ret -eq 1 ]; then
    echo "xcalar install failed"
    exit $ret
fi
rm -rf "$TMPDIR"
exit 0
