#!/bin/bash
set -e
TMPDIR=$(mktemp -d /tmp/awscli-XXXXXX)
cd $TMPDIR
curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
if command -v sudo >/dev/null; then
    SUDO='sudo -H'
fi
if command -v bsdtar >/dev/null; then
    $SUDO tar zxf awscliv2.zip
elif command -v unzip >/dev/null; then
    $SUDO unzip awscliv2.zip
else
    echo >&2 "Need unzip or bsdtar"
    $SUDO yum install -y unzip
    $SUDO unzip awscliv2.zip
fi
ver=$(aws/dist/aws --version | cut -d' ' -f1 | cut -d'/' -f2)
bundle=awscliv2-bundle-${ver}.tar.gz
tar czf $bundle aws
PREFIX=/opt/awscliv2
ITERATION=${ITERATION:-1}

$SUDO rm -rf $PREFIX
$SUDO mkdir -p $PREFIX
$SUDO aws/install -i $PREFIX -b /usr/bin
$SUDO ln -sfn ${PREFIX}/v2/current/bin/aws_completer /usr/bin/
echo 'complete -C /usr/bin/aws_completer aws' | $SUDO tee /usr/share/bash-completion/completions/aws >/dev/null
cd - >/dev/null

TAR=awscliv2-${ver}-${ITERATION}.tar
$SUDO tar cvf $TAR  -C / .${PREFIX} ./usr/bin/aws ./usr/bin/aws_completer ./usr/share/bash-completion/completions/aws

$SUDO rm -rf $TMPDIR
