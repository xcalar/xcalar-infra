#!/bin/bash

set -ex

PKG=$(rpm -qf /opt/xcalar/bin/usrnode --qf '%{NAME}')
PYPKG=$(rpm -qf /opt/xcalar/bin/python3 --qf '%{NAME}')

PIP_BUNDLE="pip-bundler-$(rpm -q $PKG --qf '%{VERSION}')-$(rpm -q $PYPKG --qf '%{VERSION}-%{RELEASE}').tar.gz"
PIP_BUNDLE_URL="${PIP_BUNDLE_BASE_URL:-https://storage.googleapis.com/repo.xcalar.net/deps/pip-bundler}/$PIP_BUNDLE"

install_pip_bundle() {
    MYTEMP=$(mktemp -d -t bundle.XXXXXX)
    cd "$MYTEMP"
    curl -fsSL "${PIP_BUNDLE_URL}" | tar zxvf -
    export PATH=/opt/xcalar/bin:$PATH
    bash -x install.sh --python /opt/xcalar/bin/python3
    cd -
    rm -rf "$MYTEMP"
}

install_pip_bundle
