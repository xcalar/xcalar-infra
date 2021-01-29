#!/bin/bash
#
# mkshar.sh creates a self extracting shell
# archive with $payload (should be a tar)
# to $output and optionally runs the provided
# $custom script
#
# example:
#    mkshar.sh rpm.tar rpm-installer.sh 'rpm -Uvh *.rpm'
#
# The contents are extracted into the current
# working directory and not managed by this
# script. This is the responsibility of the caller.
#
#
#
payload="$1"
custom="$2"

shift 2

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$payload" ]; then
    echo >&2 "$0 payload.tar <custom command or script.sh> <-d|--dir output-cache-dir>"
    exit 1
fi
if [ -t 1 ]; then
    echo >&2 "Refusing to dump to tty. Please redirect to a file"
    exit 1
fi

while [ $# -gt 0 ]; do
    cmd="$1"
    case "$cmd" in
        -d|--dir) dir="$2"; shift;;
        --) shift; break;;
        *) break;;
    esac
    shift
done
SHA1SUM="$(sha1sum $payload | awk '{print $1}')"

cat <<'EOF'
#!/bin/bash
say () {
    echo >&2 "$*"
}

verbose () {
    test "$v" = "v" && say "$*"
}
EOF
cat <<EOF
dir=$dir
SHA1SUM="$SHA1SUM"
EOF
cat <<'EOF'
extract_only="0"
while [ $# -gt 0 ]; do
    cmd="$1"
    case "$cmd" in
        -d|--dir) dir="$2"; shift;;
        -x|--extract) dir="$2"; extract_only="1"; shift;;
        -v|--verbose) v="v";;
        -h|--help) say "$0 <-v|--verbose> <-d|--dir output-dir> <-n|--dry-run>"; exit 1;;
        --) shift; break;;
        *) break;;
    esac
    shift
done
if test -z "$dir"; then
    TMPDIR=${TMPDIR:-/tmp}
    dir="$(mktemp -d $TMPDIR/mksharXXXXX)"
    trap "rm -rf $dir" EXIT
fi
extract=1
if test -e "$dir/SHA1SUM" && test "$(cat $dir/SHA1SUM 2>/dev/null)" = "$SHA1SUM"; then
    extract=0
fi
if test "$extract" = "1"; then
    mkdir -p "$dir"
    verbose "Extracting files to $dir"
    PAYLOAD_LINE=$(awk "/^__PAYLOAD__STARTS__/ {print NR + 1; exit 0; }" "$0")
    if ! tail -n+$PAYLOAD_LINE "$0" | tar -xz$v -C "$dir"; then
        tail -n+$PAYLOAD_LINE "$0" | tar -x$v -C "$dir"
    fi
    # Avoid re-extracting it next time
    echo "$SHA1SUM" > "$dir/SHA1SUM"
fi
if test "$extract_only" = "1"; then
    exit 0
fi
test "$v" = "v" && set -x
export ROOTDIR="$dir"
export MKSHARPWD="$PWD"
cd "$ROOTDIR"
#__SCRIPT__STARTS__
EOF
if test -n "$custom"; then
    if test -f "$custom"; then
        cat "$custom"
    else
        echo "$custom \"\$@\""
    fi
fi
cat <<'EOF'
#__SCRIPT__ENDS__
exit
__PAYLOAD__STARTS__
EOF
cat "$payload"
