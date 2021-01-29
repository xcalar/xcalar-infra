#!/bin/bash

set -e
SERVER="${SERVER:-zd.xcalar.net}"
FILES=(gce-control.sh)

TMPDIR=/tmp/$(id -u)/deploy/$SERVER

rm -rf "$TMPDIR"
mkdir -p "$TMPDIR/usr/local/bin"
for file in "${FILES[@]}"; do
    cp $file "$TMPDIR/usr/local/bin"
done

echo >&2 "Deploying ${#FILES[@]} files to $SERVER ..."
tar czf - -C "$TMPDIR" usr | ssh $SERVER 'sudo tar zxvf - -C / --no-same-owner'

rm -rf "$TMPDIR"
