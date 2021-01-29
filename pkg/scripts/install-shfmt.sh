#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL=https://mvdan.cc/sh/cmd/shfmt
NAME=shfmt
VERSION=2.3.0
ITERATION=${BUILD_NUMBER:-1}
DESC="A shell parser, formatter and interpreter."
LICENSE=BSD3

. $DIR/install-golang-tool.sh
