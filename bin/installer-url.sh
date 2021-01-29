#!/bin/bash
#
# Copies an installer to S3/GCS/AZBLOB, then provides a signed
# URL with $EXPIRY seconds validity
#
# shellcheck disable=SC2086,SC1091,SC2164

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$XLRINFRADIR" ]; then
    export XLRINFRADIR="$(cd "${DIR}/.." && pwd)"
fi
export PATH="$XLRINFRADIR/bin:$PATH"

. infra-sh-lib
. aws-sh-lib

# Links expire in 1 week by default. That's the max setting.
UPLOAD="gs,az"
DRYRUN=false
TESTING=${TESTING:-false}
FORCE=false

say() {
    echo >&2 "$*"
}

check_url() {
    curl -r 0-255 -sL -o /dev/null "$1" -w '%{http_code}' | grep -q '^20'
}

az_blob() {
    local cmd="$1"
    shift
    az storage blob $cmd --account-name "$ACCOUNT" --container-name "$CONTAINER" --name "$BLOB" "$@"
}

test_self () {
    export TESTING=true
    export AWS_DEFAULT_REGION=us-west-2
    TMPDIR="$(mktemp -d -t uploadXXXXXX)" || exit 1
    mkdir -p $TMPDIR || exit 1
    trap "rm -r $TMPDIR" EXIT
    T=1
    TARGETS=(${DEST:-az s3 gs})
    echo "1..$(( ${#TARGETS[@]} * 4 ))"
    for DEST in ${TARGETS[*]}; do
        INSTALLER=$TMPDIR/prod/xcalar-1.0.0-1234-installer
        if ! URL="$(${BASH_SOURCE[0]} -d $DEST $INSTALLER)"; then
            echo "not ok $T - ${DEST}: Failed to download existing installer"
            exit 1
        else
            echo "ok $T - ${DEST}: Got existing URL ${URL%\?*}"
        fi
        T=$((T+1))

        if [ "$(curl -sL "$URL")" != TEST ]; then
            echo "not ok $T - ${DEST}: Contents of file were not TEST"
            exit 1
        else
            echo "ok $T - ${DEST}: Contents of file were TEST"
        fi
        T=$((T+1))
        mkdir -p ${TMPDIR}/prod
        INSTALLER=$TMPDIR/prod/xcalar-1.0.0-1236-installer
        testText="Right now is $(date +%FT%T.%N%z)"
        echo "$testText" > $INSTALLER
        if ! URL="$(${BASH_SOURCE[0]} --force --no-cache -d $DEST $INSTALLER 2>${TMPDIR}/output.txt)"; then
            echo "not ok $T - ${DEST}: Failed to upload $INSTALLER to $DEST. $(cat $TMPDIR/output.txt)"
            exit 1
        else
            echo "ok $T - ${DEST}: Got URL ${URL}"
        fi
        T=$((T+1))

        contents="$(curl -sL "$URL")"
        if [ "$contents"  != "$testText" ]; then
            echo "not ok $T - ${DEST}: Contents of file were not \"$testText\", got \"$contents\""
            exit 1
        else
            echo "ok $T - ${DEST}: Contents of file were \"$testText\""
        fi
        T=$((T+1))
    done

    exit 0
}

if [ $# -eq 0 ]; then
    set -- -h
fi

while [ $# -gt 0 ]; do
    cmd="$1"
    case "$cmd" in
    -h | --help)
        say "Usage: $0 [-d|--dest <az|gs|s3>] [-e expiry-in-seconds (default 1w or 4w depending on cloud)] [--no-cache] [--force] [-f <path/to/installer>] [-t|-test run self test] [--] installer"
        say " upload the installer to repo.xcalar.net and print out new http url"
        exit 1
        ;;
    -e | --expiry | --expires-in)
        EXPIRY="$2"
        shift 2
        ;;
    --no-cache)
        CACHE_CONTROL="no-cache, no-store, must-revalidate, max-age=0, no-transform"
        shift
        ;;
    --use-sha1)
        USE_SHA1=1
        shift
        ;;
    -f | --file)
        if [ -n "$INSTALLER_URL" ]; then
            say "WARNING: Overriding existing environment value of INSTALLER_URL='$INSTALLER_URL' with INSTALLER='$2'"
        fi
        INSTALLER="$2"
        shift 2
        ;;
    --force)
        FORCE=true
        shift
        ;;
    -d | --dest)
        DEST="$2"
        shift 2
        ;;
    -n | --dryrun | --dry-run)
        DRYRUN=true
        shift
        ;;
    -t | --test)
        shift
        test_self
        exit $?
        ;;
    --)
        shift
        break
        ;;
    -*)
        say "ERROR: Unknown option $1"
        exit 1
        ;;
    *) break ;;
    esac
done

if [ $# -gt 0 ]; then
    if [ -n "$INSTALLER" ]; then
        say "WARNING: INSTALLER='$INSTALLER' has already been specified, but is being overwritten by extra argument $1"
    fi
    if [ -n "$INSTALLER_URL" ]; then
        say "WARNING: INSTALLER_URL='$INSTALLER_URL' has already been specified, but is being overwritten by extra argument $1"
    fi
    INSTALLER="$1"
    shift
fi

if $TESTING || test -f "$INSTALLER"; then
    if ! $TESTING; then
        INSTALLER="$(readlink_f "${INSTALLER}")"
    fi
    BUILD_SHA="$(dirname ${INSTALLER})/../BUILD_SHA"
    if test -f "$BUILD_SHA"; then
        SHAS=($(awk '{print $(NF)}' "${BUILD_SHA}" | tr -d '()'))
        SHA1="${SHAS[0]}-${SHAS[1]}"
    else
        if $TESTING; then
            SHA1="0"
        else
            SHA1="$(sha1sum "$INSTALLER" | awk '{print $1}')"
        fi
    fi
    INSTALLER_FNAME="$(basename "$INSTALLER")"
    SUBDIR="$(basename $(dirname "$INSTALLER"))"
    DEST_FNAME="${SUBDIR}/$INSTALLER_FNAME"
    test -n "$DEST" || DEST=s3

    case "$DEST" in
    gs)
        SA_URI="gs"
        SA_ACCOUNT="${SA_ACCOUNT:-repo.xcalar.net}"
        ;;
    aws|s3)
        SA_URI="s3"
        case "$AWS_DEFAULT_REGION" in
            us-east-1) SA_ACCOUNT="${SA_ACCOUNT:-xcrepoe1}";;
            us-west-2) SA_ACCOUNT="${SA_ACCOUNT:-xcrepo}";;
        esac
        ;;
    az) SA_URI="az" ;;
    esac
    SA_ACCOUNT="${SA_ACCOUNT:-xcrepo}"
    SA_PREFIX="${SA_PREFIX:-builds}"
    DEST_URI="${SA_URI}://${SA_ACCOUNT}/${SA_PREFIX}"
    if [ "$USE_SHA1" = 1 ]; then
        DEST_URL="${DEST_URI}/${SHA1}/${DEST_FNAME}"
    else
        DEST_URL="${DEST_URI}/${DEST_FNAME}"
    fi

    case "${DEST_URL}" in
    s3://*)
        export AWS_DEFAULT_REGION=$(aws_s3_region "$DEST_URL")
        EXPIRY=${EXPIRY:-604200}  # 1 week is max on AWS
        if [[ $EXPIRY -ge 604800 ]] || [[ $EXPIRY -le 0 ]]; then
            say "Invalid expiry. Must be 604800 (one week) or less and greater than 0"
            exit 1
        fi
        URL="$(aws s3 presign --expires-in $EXPIRY "$DEST_URL")"

        if ! $FORCE && check_url "$URL"; then
            echo "$URL"
            exit 0
        fi
        say "Uploading $INSTALLER to $DEST_URL"
        if aws s3 cp --metadata-directive REPLACE ${CACHE_CONTROL+--cache-control "${CACHE_CONTROL}"} --only-show-errors "$INSTALLER" "$DEST_URL" >&2; then
            # S3 eventual consistency at work
            sleep 1
        else
            say "Failed to upload to $INSTALLER to $DEST_URL"
            exit 1
        fi
        if check_url "$URL"; then
            echo "$URL"
            exit 0
        fi
        echo >&2 "Failed to verify $URL"
        exit 1
        ;;
    gs://*)
        URL="https://storage.googleapis.com/${DEST_URL#gs://}"
        LOCK="${DEST_URL}.lock"
        while ! echo "$(hostname) $$ $(date)" | gsutil -q -h "x-goog-if-generation-match:0" cp - "$LOCK"; do
            say "Waiting for existing upload to complete ..."
            sleep 10
        done
        if $FORCE || ! gsutil ls "$DEST_URL" > /dev/null 2>&1; then
            say "Uploading $INSTALLER to $DEST_URL"
            until gsutil -m -o GSUtil:parallel_composite_upload_threshold=100M \
                cp -c "$INSTALLER" "$DEST_URL" >&2; do
                sleep 1
            done
            if [ -n "$CACHE_CONTROL" ]; then
                gsutil setmeta -h "Cache-Control:$CACHE_CONTROL" "$DEST_URL" >&2
            fi
        fi
        while ! gsutil -q rm "$LOCK"; do
            sleep 1
        done
        if check_url "$URL"; then
            echo "$URL"
            exit 0
        fi
        ;;
    az://*)
        DEST_URL="${DEST_URL#az://}"
        ACCOUNT="${DEST_URL%%/*}"
        CONTAINER="${DEST_URL#*/}"
        CONTAINER="${CONTAINER%%/*}"
        BLOB=${DEST_URL#${ACCOUNT}/${CONTAINER}/}
        EXPIRY=${EXPIRY:-2419200}  # 4 weeks
        EXPIRES="$(date -d "$EXPIRY seconds" '+%Y-%m-%dT%H:%MZ')"
        URL="$(az_blob url -otsv)"
        CODE="$(az_blob generate-sas --permissions r --expiry $EXPIRES -otsv)"
        URL="${URL}?${CODE}"
        if ! $FORCE && check_url "$URL"; then
            echo "$URL"
            exit 0
        fi
        if ! az_blob upload -f "$INSTALLER" ${CACHE_CONTROL+--content-cache-control "${CACHE_CONTROL}"} >&2; then
            say "Failed to upload to $DEST_URL"
            exit 1
        fi
        if check_url "$URL"; then
            echo "$URL"
            exit 0
        fi
        say "Failed to verify $URL"
        exit 1
        ;;
    *)
        say "Unknown resource ${DEST_URL}"
        exit 1
        ;;
    esac
elif [[ ${INSTALLER} =~ ^http[s]?:// ]]; then
    if check_url "${INSTALLER}"; then
        say "URL Verified OK"
        echo $INSTALLER
        exit 0
    fi
elif [[ ${INSTALLER} =~ ^s3:// ]]; then
    export AWS_DEFAULT_REGION=$(aws_s3_region "$INSTALLER")
    if aws_s3_head_object "${INSTALLER}" >/dev/null; then
        aws s3 presign --expires-in $EXPIRY "${INSTALLER}"
        exit $?
    fi
fi

say "Unable to locate $INSTALLER as either a valid file or URL"
exit 1
