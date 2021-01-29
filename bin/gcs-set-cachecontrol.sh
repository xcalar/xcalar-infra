#!/bin/bash
#
# Disable http caching for certain objects (like repo databases)

CACHE_CONTROL="${CACHE_CONTROL:-no-cache, no-store, must-revalidate, max-age=0, no-transform}"

gcs_dontcache () {
    (set -x
    gsutil -m setmeta -h "Cache-Control: $CACHE_CONTROL" "$@")
}

DEFAULT=('gs://repo.xcalar.net/rpm-deps/el6/x86_64/repodata/*'
'gs://repo.xcalar.net/rpm-deps/el7/x86_64/repodata/*'
'gs://repo.xcalar.net/mirror/epel/6Server/x86_64/repodata/*'
'gs://repo.xcalar.net/mirror/epel/7Server/x86_64/repodata/*'
'gs://repo.xcalar.net/mirror/rhel/6Server/x86_64/repodata/*'
'gs://repo.xcalar.net/mirror/rhel/7Server/x86_64/repodata/*'
'gs://repo.xcalar.net/apt/ubuntu/conf/*'
'gs://repo.xcalar.net/apt/ubuntu/db/*'
'gs://repo.xcalar.net/apt/ubuntu/dists/trusty/main/binary-amd64/*')

test $# -eq 0 && set -- "${DEFAULT[@]}"
gcs_dontcache "$@"
