#!/bin/bash

# Use s3 select to  get 1 line from the parquet

bucket_and_key() {
    local bucket="${1#s3://}"
    bucket="${bucket%%/*}"
    local key="${1#s3://}"
    key="${key#${bucket}/}"
    echo $bucket $key
}

s3cp() {
    eval "$@"
}

s3_list_v2() {
    aws s3api list-objects-v2 --bucket "$1" --prefix "$2" \
        --query 'Contents[*].[LastModified,Key]' \
        --output text
}

s3_inventory() {
    #local inv="s3://xclogs/inventory/${bucet}/${bucket}/2020-01-19T04-00Z/manifest.json
    local dump=0
    if [ "$1" == "--dump" ]; then
        dump=1
        shift
    fi
    local bucket="$1"
    local date="${2:-$(date --utc +'%Y-%m-')}"
    local s3logs="${3:-xclogs}"
    local manifest
    if ! manifest="$(
        s3_list_v2 "$s3logs" "inventory/${bucket}/${bucket}/${date}" \
            | grep '/manifest.json$' \
            | sort -n \
            | tail -1 \
            | cut -d$'\t' -f2-)"; then
        echo >&2 "Failed to list-objects-v2"
        return 1
    fi
    local manifest_files file
    manifest_files=($(aws s3 cp "s3://${s3logs}/${manifest}"  - | jq -r '.files[].key'))
    for file in "${manifest_files[@]}"; do
        if ((dump)); then
            aws s3 cp s3://${s3logs}/${file} - | gzip -dc
        else
            echo "s3://${s3logs}/${file}"
        fi
    done
}

s3_select() {
    local bucket key comp='NONE'
    local exp output input_options=''
    local output_type='json' count=1
    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            --bucket|-b) bucket="$1"; shift;;
            --key|-k) key="$1"; shift;;
            --expression) exp="$1"; shift;;
            --input-type) input_type="$1"; shift;;
            --output-type) output_type="$1"; shift;;
            --output) output="$1"; shift;;
            --comp) comp="$1"; shift;;
            --count) count="$1"; shift;;
            --with-header) input_options='"FileHeaderInfo":"Use"';;
        esac
    done
    if [ -z "$input_type" ]; then
        if [[ "$key" =~ \.[Cc][Ss][Vv] ]]; then
            input_type=CSV
        elif [[ "$key" =~ \.[Jj][Ss][Oo][Nn] ]]; then
            input_type=JSON
        else
            input_type=Parquet
        fi
        if [[ "$key" =~ \.[Gg][Zz]$ ]]; then
            comp='GZIP'
        elif [[ "$key" =~ \.[Bb][Zz][Ii][Pp]$ ]]; then
            comp='BZIP2'
        fi
    fi
    if [ -z "$output" ]; then
        output="$(basename "$key")"
        output="delme${output%.*}.${output_type}"
    fi
    if [ -z "$exp" ]; then
        exp="select * from s3object LIMIT $count"
    fi
#    cat <<-EOF|python >&2
#	import os
#	print(os.environ['PATH'])
#	EOF
    if aws s3api select-object-content \
        --bucket "$bucket" \
        --key "$key" \
        --input-serialization '{"CompressionType":"'$comp'","'${input_type}'":{'$input_options'}}' --output-serialization '{"'${output_type^^}'":{}}' \
        --expression-type SQL --expression "$exp" $output; then
        cat $output
        if [[ $output =~ ^delme ]]; then
            rm $output
        fi
        return 0
    fi
    return 1
}

check_s3() {
    if ! [[ "$1" =~ ^s3:// ]]; then
        echo >&2
        echo >&2 "ERROR: Must specify a S3Uri (eg, s3://xcfield/instantdatamart/parquet/600_sparse0.0 )"
        echo >&2
        exit 1
    fi
}

do_schema() {
    check_s3 "$1"
    S3OBJ="$1"
    BK=($(bucket_and_key "$S3OBJ"))
    output="$(mktemp -t s3-select-XXXXXX.json)"
    s3temp="s3://${BK[0]}/tmp/$(basename $output)"
    s3_select --bucket ${BK[0]} --key "${BK[1]}" --count 3 | aws s3 cp - "$s3temp"
    python app.py "$s3temp" | jq -r .
}

do_parse() {
    check_s3 "$1"
    S3OBJ="$1"
    shift
    BK=($(bucket_and_key "$S3OBJ"))
    s3_select --bucket ${BK[0]} --key "${BK[1]}" "$@"
}

do_inventory() {
    s3_inventory "$@"
}

usage() {
    cat <<EOF
    usage $0 schema S3Uri outputFileOrS3Uri
             parse S3Uri outputFileOrS3Uri
             inventory [--dump] bucket [optional: date iso8601] [optional: logs bucket]
    Ex:
      $0 schema s3://xcfield/instantdatamart/parquet/600_sparse0.0 | head -20
      $0 parse s3://xcfield/instantdatamart/tests/readings_medium.csv.gz --with-header --expression "SELECT \"id\",\"date\",\"country\",\"ipAddress\" from s3object s WHERE s.\"country\" LIKE '%Egypt%' LIMIT 5"
      $0 inventory xcfield

EOF
}

[ $# -gt 0 ] || set -- --help

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -h|--help) usage; exit 0;;
        schema) do_schema "$@"; exit;;
        parse) do_parse "$@"; exit;;
        inventory) do_inventory "$@"; exit;;
        *) usage >&2; echo >&2 "ERROR: Unknown commandline $cmd"; exit 1;;
    esac
done
# vim: ft=sh

