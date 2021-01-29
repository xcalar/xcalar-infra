#!/bin/bash
NAME=direnv
VER=2.15.2
ITERATION="${ITERATION:-1}"
REPO=github.com/direnv/direnv

TMPDIR=${TMPDIR:-/tmp}/`id -un`/${NAME}
DESTDIR=$TMPDIR/rootfs
export GOPATH=$TMPDIR/go
SRCDIR=${GOPATH}/src/${REPO}

set -e
rm -rf $TMPDIR

#git clone https://${REPO} ${SRCDIR}
#cd ${SRCDIR}
go get -u -v $REPO
cd $SRCDIR
make DESTDIR=$DESTDIR/usr install
cd -

fpm -s dir -t deb -n $NAME --version ${VER} --iteration ${ITERATION} --description "direnv is an environment switcher for the shell" --url https://direnv.net --license MIT -C $DESTDIR usr
fpm -s dir -t rpm -n $NAME --version ${VER} --iteration ${ITERATION} --description "direnv is an environment switcher for the shell" --url https://direnv.net --license MIT -C $DESTDIR usr
