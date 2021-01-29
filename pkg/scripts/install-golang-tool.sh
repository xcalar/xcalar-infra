#!/bin/bash
# Common file for Golang based tools

TMPDIR="$(mktemp -d --tmpdir  ${NAME}.XXXXXX)"
TMPDIR="${TMPDIR:-/tmp/`id -u`}/${NAME}-${VERSION}"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

export GOPATH=$TMPDIR/go
mkdir -p ${GOPATH}/{bin,src}

go get -u -v "${URL##https://}"

FPM_COMMON=(-n "${NAME}" --license "${LICENSE}" -v "${VERSION}" --iteration "${ITERATION}" --url "${URL}" --description "${DESC}" -f "${GOPATH}/bin/${NAME}=/usr/bin/${NAME}")

ls -al ${GOPATH}/bin

fpm -s dir -t deb "${FPM_COMMON[@]}"
fpm -s dir -t rpm "${FPM_COMMON[@]}"
