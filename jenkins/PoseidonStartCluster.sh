#!/bin/bash -x

set -e

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

if [ ! -z "$LDAP_CONFIG_PATH" ]; then
    localPath="$LDAP_CONFIG_PATH"
    if [ ! -f $localPath ]; then
        echo "LDAP_CONFIG_PATH $localPath not found"
        localPath="$XLRINFRADIR/$LDAP_CONFIG_PATH"
        if [ ! -f $localPath ]; then
            echo "LDAP_CONFIG_PATH $localPath not found"
            exit 1
        fi
    fi
    echo "Using LDAP_CONFIG_PATH $localPath"
fi

source "$XLRINFRADIR/bin/clusterCmds.sh"
initClusterCmds

installer="$INSTALLER_PATH"

cluster="$CLUSTER"

startCluster "$installer" "$NUM_INSTANCES" "$cluster"
ret=$?
if [ "$ret" != "0" ]; then
    exit $ret
fi

try=0
until startupDone "$cluster" ; do
    echo "Waited $try seconds for Xcalar to come up"
    sleep 1
    try=$(( $try + 1 ))
    if [[ $try -gt 3600 ]]; then
        echo "Timeout waiting for Xcalar to come up"
        exit 1
     fi
done

stopXcalar "$cluster"

clusterSsh "$cluster" "sudo sysctl -w net.ipv4.tcp_keepalive_time=60 net.ipv4.tcp_keepalive_intvl=30 net.ipv4.tcp_keepalive_probes=100"

clusterSsh "$cluster" "sudo yum install -y gcc-c++ wget tmux python-devel"

# Install gdb-8.0
if [ "$InstallGdb8" = "true" ]; then
    clusterSsh "$cluster" "sudo curl http://storage.googleapis.com/repo.xcalar.net/rpm-deps/xcalar-deps.repo -o /etc/yum.repos.d/xcalar-deps.repo"
    clusterSsh "$cluster" "sudo yum install -y optgdb8"
    clusterSsh "$cluster" "sudo ln -sfn /opt/gdb8/bin/gdb /usr/local/bin/gdb"
    clusterSsh "$cluster" "sudo ln -sfn /opt/gdb8/bin/gdb /usr/bin/gdb"
fi

# Set up SerDes
#clusterSsh $cluster "mkdir -p $XdbLocalSerDesPath"
#clusterSsh $cluster "chmod +w $XdbLocalSerDesPath"
#clusterSsh $cluster "sudo chown -R xcalar:xcalar $XdbLocalSerDesPath"

# Remount xcalar with noac for liblog stress
#clusterSsh $cluster "sudo umount /mnt/xcalar"
#clusterSsh $cluster "sudo mount -o noac /mnt/xcalar"

clusterSsh "$cluster" "sudo sed -ie 's/Constants.XcMonSlaveMasterTimeout=.*/Constants.XcMonSlaveMasterTimeout=$XcMonSlaveMasterTimeout/' /etc/xcalar/default.cfg"
clusterSsh "$cluster" "sudo sed -ie 's/Constants.XcMonMasterSlaveTimeout=.*/Constants.XcMonMasterSlaveTimeout=$XcMonMasterSlaveTimeout/' /etc/xcalar/default.cfg"
clusterSsh "$cluster" "echo \"$FuncTestParam\" | sudo tee -a /etc/xcalar/default.cfg"

if [ ! -z "$LDAP_CONFIG_PATH" ]; then
    # localPath validated above
    remotePath="/mnt/xcalar/config/ldapConfig.json"
    printf -v safeString "%q" `cat $localPath`
    node=$(getSingleNodeFromCluster "$cluster")
    nodeSsh "$cluster" "$node" "echo $safeString | sudo tee -a $remotePath"
    nodeSsh "$cluster" "$node" "sudo chown xcalar:xcalar $remotePath"
    nodeSsh "$cluster" "$node" "sudo chmod 600 $remotePath"
fi

clusterSsh "$cluster" "echo \"vm.min_free_kbytes=$KernelMinFreeKbytes\" | sudo tee -a /etc/sysctl.conf"
clusterSsh "$cluster" "sudo sysctl -p"

restartXcalar "$cluster"
ret=$?
if [ "$ret" != "0" ]; then
    echo "Failed to bring Xcalar up"
    exit $ret
fi

clusterSsh "$cluster" "echo \"XLRDIR=/opt/xcalar\" | sudo tee -a /etc/bashrc"

# Set up defaultAdmin.json
clientSecret="$XLRDIR/src/bin/sdk/xdp/xcalar/external/client_secret.json"
xiusername=`cat $clientSecret | jq .xiusername -cr`
xipassword=`cat $clientSecret | jq .xipassword -cr`
credArray="`$XLRDIR/pkg/gui-installer/default-admin.py -e 'support@xcalar.com' -u $xiusername -p $xipassword`"
# only want to send cmd to one node in the cluster
node=$(getSingleNodeFromCluster "$cluster")
nodeSsh "$cluster" "$node" 'XLRROOT="$(cat /etc/xcalar/default.cfg | grep XcalarRootCompletePath | cut -d= -f2)"; cfgFile="$XLRROOT/config/defaultAdmin.json"; echo '"'""$credArray""'"' | sudo tee "$cfgFile"; sudo chown xcalar:xcalar "$cfgFile" ; sudo chmod 600 "$cfgFile"'
