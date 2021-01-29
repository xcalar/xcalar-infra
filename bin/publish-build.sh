#!/bin/bash

BUCKET=${BUCKET:-gs://repo.xcalar.net}
DOMAIN=${DOMAIN:-$(basename $BUCKET)}
PUBDIR=${PUBDIR:-builds}
WWWROOT="${WWWROOT:-http://$DOMAIN/$PUBDIR}"
LOGNAME="${LOGNAME:-$(id -n)}"

say () {
    echo >&2 "$*"
}

die () {
    echo >&2 "ERROR: $*"
    exit 1
}

check_link () {
    test -z "$1" && return 1
	curl -IsL "$1" | head -n 1 | grep -q '200 OK'
}

blob_sdk_check () {
    if ! blob_ls "$1" >/dev/null; then
        say "Unable to read $BUCKET/"
        case "$1" in
            s3://*)
                say "Do you have access to AWS and the awscli installed? See http://wiki.int.xcalar.com/mediawiki/index.php/AWS_Acccess"
                ;;
            gs://*)
                say "Do you have access to GCE and the GCloud SDK? See http://wiki.int.xcalar.com/mediawiki/index.php/GCE"
                ;;
            *)
                say "Unsupported URI $1"
                ;;
        esac
        return 1
    fi
}

blob_ls () {
    if [[ $1 =~ s3:// ]]; then
        aws s3 ls "$1"
    elif [[ $1 =~ gs:// ]]; then
        gsutil ls "$1"
    else
        return 1
    fi
}

blob_cp () {
    local log="$TMPDIR/upload-$(basename "$1").log"
    if [[ $2 =~ s3:// ]]; then
        aws s3 cp "$@" >> "$log"
    elif [[ $2 =~ gs:// ]]; then
        until gsutil -m -o GSUtil:parallel_composite_upload_threshold=100M cp -c -L "$log" "$@" >/dev/null ; do
            sleep 1
        done
    else
        return 1
    fi
}


publish_build () {
    if test -f "$1"; then
        INSTALLER="$(readlink -f ${1})"
        INSTALLER_FNAME="$(basename $INSTALLER)"
    elif [[ $1 =~ ${WWWROOT} ]]; then
        echo "$1"
        return 0
    elif [[ $1 =~ ^http[s]?:// ]]; then
        INSTALLER_FNAME="$(basename $1)"
        INSTALLER="${TMPDIR}/${INSTALLER_FNAME}"
        curl -fsSL "$1" > "${INSTALLER}.$$" && mv "${INSTALLER}.$$" "$INSTALLER" || return 1
    else
        say "Can't read file $1"
        return 1
    fi
    URL="$WWWROOT/$INSTALLER_FNAME"
    if check_link "$URL"; then
        echo "$URL"
        return 0
    fi
    BUCKET_URL="$BUCKET/$PUBDIR/$INSTALLER_FNAME"
    blob_ls "$BUCKET_URL" && echo "$URL" && return 0
    say "Uploading $INSTALLER to $BUCKET_URL"
    blob_cp "$INSTALLER" "$BUCKET_URL" && echo "$URL" && return 0
    return 1
}

publish_main () {
    blob_sdk_check "$BUCKET" && \
    publish_build "$1"
}

TMPDIR="${TMPDIR:-/tmp/$LOGNAME/publish-build}"
mkdir -p "$TMPDIR" || die "Failed to create $TMPDIR"
publish_main "$@"
