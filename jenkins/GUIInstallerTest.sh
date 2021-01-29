#!/bin/bash

# INPUT: path to gui installer
# Spins up an azure instance and passes if installer installs correctly and cluster comes up
# Notes: if installer fails it leaves behind the tmpdir and azure instance for debugging. ssh key
# for instance access is in the tmpdir

if [ -z "$XLRINFRADIR" ]; then
    XLRINFRADIR="$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)"
fi
export XLRINFRADIR
export PATH=$XLRINFRADIR/bin:$PATH

. infra-sh-lib || exit 1
. azure-sh-lib || exit 1



cleanup() {
    rm -rf $JOBTMPDIR
    az group delete -g $GROUP --no-wait -y
}

if [ -z "$INSTALLER" ]; then
    echo "Must specify an installer to test"
    exit 1
fi

BUILD_NUMBER=${BUILD_NUMBER:-1}

if [ -n "$AZURE_CLIENT_ID" ]; then
    az_login
fi

GROUP=GUIInstallerTest-${BUILD_NUMBER}-rg
NAME=GUIInstallerTest-${BUILD_NUMBER}-vm

set -e

LOCATION=${LOCATION:-westus2}
JOBTMPDIR="${TMPDIR:-/tmp/gui-installer-test-$(id -u)/$$}"

mkdir -p $JOBTMPDIR

if az group show -g $GROUP > /dev/null 2>&1; then
    die "Group $GROUP already exists, conflicting test... exiting"
else
    az group create -g $GROUP -l $LOCATION -ojson > /dev/null
fi

trap cleanup EXIT

SSH_KEY_FILE=$XLRINFRADIR/jenkins/jenkins_insecure_key
chmod 600 $XLRINFRADIR/jenkins/jenkins_insecure_key
SUBNETID=$(az network vnet subnet show -g xcalardev-rg --name default --vnet-name xcalardev-vnet --query id -o tsv)

az vm create \
    --resource-group $GROUP \
    --name $NAME\
    --image "OpenLogic:CentOS:7.5:latest" \
    --admin-username azureuser \
    --ssh-key-value ${SSH_KEY_FILE}.pub \
    --public-ip-address "" \
    --nsg "" \
    --subnet $SUBNETID \
    --size Standard_D8s_v3

PVT_IP=$(az vm show -g $GROUP -n $NAME -d --query privateIps -otsv)

# Some image setup for the installer to succeed

# add some swap or xcmonitor will fail to start
sshOpts="-A -oStrictHostKeyChecking=no -oLogLevel=ERROR -oUserKnownHostsFile=/dev/null -i $SSH_KEY_FILE azureuser@${PVT_IP}"
ssh $sshOpts 'sudo id && free -m'
ssh $sshOpts 'sudo dd if=/dev/zero of=/swapfile bs=1M count=1000 && sudo mkswap /swapfile && sudo swapon /swapfile && free -m'

# add epel for freetds
ssh $sshOpts 'sudo yum install -y epel-release && sudo yum install -y freetds'

ADMIN_USERNAME=${ADMIN_USERNAME:-xdpadmin}
ADMIN_EMAIL=${ADMIN_EMAIL:-xdpadmin@xcalar.com}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Welcome1}

echo "Extracting installer..."
$INSTALLER -x $JOBTMPDIR

TMPOPTXCALAR="${JOBTMPDIR}/opt/xcalar"
export NO_PING
export XCE_HTTPS_PORT=8543
export XCE_EXP_PORT=12224
export XCE_INSTALLER_ROOT=$JOBTMPDIR/opt/xcalar
export TMPDIR=${XCE_INSTALLER_ROOT}/tmp
export PATH="${TMPOPTXCALAR}/bin:$PATH"
HOSTS_FILE=${TMPOPTXCALAR}/config/hosts.txt
LICENSE_FILE=${TMPOPTXCALAR}/config/license.txt


echo $PVT_IP > $HOSTS_FILE
echo "Invalid" > $LICENSE_FILE

set +e

$TMPOPTXCALAR/installer/cluster-install.sh \
    -h $HOSTS_FILE \
    -l azureuser \
    --priv-hosts-file $HOSTS_FILE \
    -p 22 --ssh-mode key \
    -i $SSH_KEY_FILE \
    --license-file $LICENSE_FILE \
    --nfs-mode create \
    --default-admin \
    --admin-username $ADMIN_USERNAME \
    --admin-email $ADMIN_EMAIL \
    --admin-password $ADMIN_PASSWORD \
    --pre-config \
    --install-dir /opt/xcalar \
    --enable-hotPatches

# workaround due to current bug with xcalar not starting right after install
ssh $sshOpts 'XC_ROOT="/opt/xcalar/opt/xcalar" ; export PATH="$XC_ROOT/bin:$PATH" ; xcalarctl stop-supervisor && xcalarctl start'
rc=$?

if [ "$rc" != "0" ]; then
    if [ "$DEBUG" = "true" ]; then
        trap '' EXIT
    fi
    exit $rc
fi
exit 0
