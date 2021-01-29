#!/bin/bash

DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"

if test -z "$XLRINFRADIR"; then
    export XLRINFRADIR="$(cd "$DIR"/.. && pwd)"
fi

export VmProvider=${VmProvider:-GCE}

XCE_FILE=""
if [ "$IS_RC" = "true" ]; then
    XCE_FILE="$XLRDIR"/src/data/XcalarLic.key.prod
else
    XCE_FILE="$XLRDIR"/src/data/XcalarLic.key
fi
XCE_LICENSE=$(cat "$XCE_FILE" | gzip | base64 -w0)
export XCE_LICENSE="$XCE_LICENSE" # only GCE needs this as an env var

OVIRTTOOL_DOCKER_WRAPPER="$XLRINFRADIR"/bin/ovirttool_docker_wrapper
OVIRTTOOL_CLUSTER_OPS="$XLRINFRADIR"/ovirt/ovirtcluster-operations.sh

initClusterCmds() {
    if [ "$VmProvider" = "GCE" ]; then
        bash /netstore/users/jenkins/slave/setup.sh
    elif [ "$VmProvider" = "Azure" ]; then
        az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID && az account set --subscription $AZURE_SUBSCRIPTION_ID
    elif [ "$VmProvider" = "Ovirt" ]; then
        return 0 # there is no setup required in the Ovirt case
    else
        echo "Unknown VmProvider $VmProvider"
        exit 1
    fi
}

startCluster() {
    local installer="$1"
    local numInstances="$2"
    local clusterName="$3"

    if [ "$VmProvider" = "GCE" ]; then
        # gce-cluster.sh will based xcalar license on an XCE_LICENSE env variable
        "$XLRINFRADIR"/gce/gce-cluster.sh "$installer" "$numInstances" "$clusterName"
        return $?
    elif [ "$VmProvider" = "Azure" ]; then
        # azure-cluster.sh bases xcalar license on what you supply to -k option
        "$XLRINFRADIR"/azure/azure-cluster.sh -i "$installer" -c "$numInstances" -n "$clusterName" -t "$INSTANCE_TYPE" -k "$XCE_LICENSE"
        return $?
    elif [ "$VmProvider" = "Ovirt" ]; then
        # if you don't pass ovirttool --licfile option, it will look for lic file
        # in $XLRINFRA/ovirt for XcalarLic.key;
        # hack is putting it there for now (args which take arbitrary files paths,
        # need to be mounted in Docker container that ovirttool_docker_wrapper sets up)
        local lic_file_dest="$XLRINFRADIR"/ovirt/XcalarLic.key
        cp "$XCE_FILE" "$lic_file_dest"
        # --listen in case its single node; will set node.0.ipAddr to hostname so jenkins slave can query it;
        "$XLRINFRADIR"/bin/ovirttool_docker_wrapper --count "$numInstances" --vmbasename "$clusterName" --installer http:/"$installer" --norand --listen --ram 64
        return $?
    fi

    echo 2>&1 "Unknown VmProvider $VmProvider"
    return 1
}

# print node arg required for nodeSsh for each node in a cluster (not necessarily hostname)
# one line per node
getNodes() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to getNodes" >&2
        exit 1
    fi
    local cluster="$1"
    if [ "$VmProvider" = "GCE" ]; then
        gcloud compute instances list | grep $cluster | cut -d \  -f 1
        return ${PIPESTATUS[0]}
    elif [ "$VmProvider" = "Azure" ]; then
        "$XLRINFRADIR"/azure/azure-cluster-info.sh "$cluster" | awk '{print $0}'
        return ${PIPESTATUS[0]}
    elif [ "$VmProvider" = "Ovirt" ]; then
        bash "$OVIRTTOOL_CLUSTER_OPS" --cluster "$cluster" --list
        return $?
    fi
    echo 2>&1 "Unknown VmProvider $VmProvider"
    return 1
}

# print ip or fqdn of each node in a cluster to stdout
getRealNodeNames() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to getRealNodeNames" >&2
        exit 1
    fi
    local cluster="$1"
    if [ "$VmProvider" = "GCE" ]; then
        # NOTPREEMPTIBLE Is Jenkins param in SystemStartTest; GCE vms created
        # with preemptible option have additional col in output
        if [ "$NOTPREEMPTIBLE" != "1" ]; then
            gcloud compute instances list | grep $cluster | awk '/RUNNING/ {print $6}'
            return ${PIPESTATUS[0]}
        else
            gcloud compute instances list | grep $cluster | awk '/RUNNING/ {print $5}'
            return ${PIPESTATUS[0]}
        fi
    elif [ "$VmProvider" = "Azure" ]; then
        "$XLRINFRADIR"/azure/azure-cluster-info.sh "$cluster" | awk '{print $0}'
        return ${PIPESTATUS[0]}
    elif [ "$VmProvider" = "Ovirt" ]; then
        bash "$OVIRTTOOL_CLUSTER_OPS" --cluster "$cluster" --list --verbose | awk '{print $2}'
        return ${PIPESTATUS[0]}
    fi
    echo 2>&1 "Unknown VmProvider $VmProvider"
    return 1

}

# send an ssh cmd to all nodes beginning with a given string in Ovirt
# (so for cluster: send cluster basename, for a single node - even one withint a cluster,
# just send that node's exact vm name)
# (@TODO: If cluster basename sent, verify all nodes matching are in same cluster)
ovirtSsh() {
    if [ -z "$1" ]; then
        echo "Must supply cluster to send ssh cmd to" >&2
        exit 1
    fi
    local cluster="$1"
    shift
    local tool_cmd="bash $OVIRTTOOL_CLUSTER_OPS --cluster $cluster --ssh '$@'"
    eval "$tool_cmd"
    return $?
}

nodeSsh() {
    # cluster arg only required for Azure case
    if [ "$VmProvider" = "Azure" ] && [ -z "$1" ]; then
        echo "Must provide a cluster to nodeSsh for the Azure case" >&2
        exit 1
    fi
    if [ -z "$2" ]; then
        echo "Must provide a node as second arg to nodeSsh" >&2
        exit 1
    fi
    local cluster="$1"
    local node="$2"
    shift 2
    if [ "$VmProvider" = "GCE" ]; then
        gcloud compute ssh --ssh-flag=-tt "$node" --zone us-central1-f -- "$@"
        return $?
    elif [ "$VmProvider" = "Azure" ]; then
        "$XLRINFRADIR"/azure/azure-cluster-ssh.sh -c "$cluster" -n "$node" -- "$@"
        return $?
    elif [ "$VmProvider" = "Ovirt" ]; then
        ovirtSsh "$cluster" "$@"
        return $?
    fi

    echo 2>&1 "Unknown VmProvider $VmProvider"
    return 1
}

# send ssh cmd to all nodes in a cluster
clusterSsh() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to clusterSsh" >&2
        exit 1
    fi
    local cluster="$1"
    shift
    if [ "$VmProvider" = "GCE" ]; then
        "$XLRINFRADIR"/gce/gce-cluster-ssh.sh "$cluster" "$@"
        return $?
    elif [ "$VmProvider" = "Azure" ]; then
        "$XLRINFRADIR"/azure/azure-cluster-ssh.sh -c "$cluster" -- "$@"
        return $?
    elif [ "$VmProvider" = "Ovirt" ]; then
        ovirtSsh "$cluster" "$@"
        return $?
    fi

    echo "Unknown VmProvider $VmProvider"
    return 1
}

stopXcalar() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to stopXcalar" >&2
        exit 1
    fi
    clusterSsh "$1" "sudo systemctl stop xcalar"
}

restartXcalar() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to restartXcalar" >&2
        exit 1
    fi
    local cluster="$1"
    local clusterHosts=($(getNodes "$cluster"))
    set +e
    stopXcalar "$cluster"
    clusterSsh $cluster "sudo systemctl status xcalar"
    local startMsg="Usrnodes started"
    local statusCmd="/etc/rc.d/init.d/xcalar status"
    if nodeSsh "$cluster" "${clusterHosts[0]}" \
               "sudo systemctl cat xcalar-usrnode.service 2>&1 >/dev/null"; then
        startMsg="usrnode --nodeId"
        statusCmd="systemctl status xcalar-usrnode.service"
    fi
    clusterSsh "$cluster" "sudo systemctl start xcalar" 2>&1
    local host
    for host in "${clusterHosts[@]}"; do
        local ret=1
        local numRetries=3600
        local try=0
        while [ $ret -ne 0 -a "$try" -lt "$numRetries" ]; do
            sleep 1s
            nodeSsh "$cluster" "$host" "sudo $statusCmd 2>&1 | grep -q '$startMsg'" 2>&1
            ret=$?
            try=$(( $try + 1 ))
        done
        if [ $ret -eq 0 ]; then
            echo "Node $host ready"
        else
            echo "Error while waiting for node $ii to come up"
            return 1
        fi
    done
    echo "All nodes ready"
    set -e
}

genSupport() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to genSupport" >&2
        exit 1
    fi
    clusterSsh "$1" "sudo /opt/xcalar/scripts/support-generate.sh"
}

startupDone() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to startupDone" >&2
        exit 1
    fi
    local cluster="$1"
    if [ "$VmProvider" = "GCE" ]; then
        local node
        for node in $(getNodes "$cluster"); do
            nodeSsh "$cluster" "$node" "sudo journalctl -r" | grep -q "Startup finished"
            ret=$?
            if [ "$ret" != "0" ]; then
                return $ret
            fi
        done
        return 0
    elif [ "$VmProvider" = "Azure" ]; then
        # azure-cluster.sh is synchronous. When it returns, either it has run to completion or failed
        return 0
    elif [ "$VmProvider" = "Ovirt" ]; then
        # nothing yet
        return 0
    fi

    echo "Unknown VmProvider $VmProvider"
    return 1
}

clusterDelete() {
    if [ -z "$1" ]; then
        echo "Must provide a cluster to clusterDelete" >&2
        exit 1
    fi
    local cluster="$1"
    if [ "$VmProvider" = "GCE" ]; then
        "$XLRINFRADIR"/gce/gce-cluster-delete.sh "$cluster"
    elif [ "$VmProvider" = "Azure" ]; then
        "$XLRINFRADIR"/azure/azure-cluster-delete.sh "$cluster"
    elif [ "$VmProvider" = "Ovirt" ]; then
        # get hostnames of nodes in the cluster, in comma sep list
        local nodes_list
        local nodes_list=$(getNodes "$cluster" | paste -sd "," -)
        "$OVIRTTOOL_DOCKER_WRAPPER" --delete "$nodes_list"
    else
        echo 2>&1 "Unknown VmProvider $VmProvider"
        exit 1
    fi
}

# print to stdout, the hostname of just the first node in <cluster>,
# from the list of getNodes <cluster>
getSingleNodeFromCluster() {
    if [ -z "$1" ]; then
        echo "Must specify cluster to getSingleNodeFromCluster" >&2
        exit 1
    fi
    local nodes_list
    nodes_list=$(getNodes "$1")
    echo "$nodes_list" | head -1
}

# prints git sha of Xcalar version installed on cluster, to stdout
gitSha() {
    if [ -z "$1" ]; then
        echo "Must supply a cluster name to clusterCmds:gitSha" >&2
        exit 1
    fi
    local version
    if version=$(cloudXccli "$1" -c version) ; then
        echo "$version" | head -n1 | cut -d\  -f3 | cut -d- -f5
    else
        echo "Exiting the test as Cluster is not up" >&2
        exit 1
    fi
}

cloudXccli() {
    if [ -z "$1" ]; then
        echo "Must specify cluster to cloudXccli" >&2
        exit 1
    fi
    local cluster="$1"
    shift

    # only want to send to one node in the cluster
    local node=$(getSingleNodeFromCluster $cluster)
    local cmd="nodeSsh $cluster $node \"sudo\" \"/opt/xcalar/bin/xccli\""
    local arg
    for arg in "$@"; do
        arg="${arg//\\/\\\\}"
        arg="${arg//\"/\\\"}"
        cmd="$cmd \"$arg\""
    done
    $cmd
}


clusterCollectCoverage() {
    # Expects the following from Jenkins Environment
    #
    # JOB_NAME
    # BUIlD_NUMBER
    # PERSIST_COVERAGE_ROOT

    cvgRoot=${PERSIST_COVERAGE_ROOT}/${JOB_NAME}/${BUILD_NUMBER}
    echo "COVERAGE cvgRoot: $cvgRoot"

    if [ -z "$1" ]; then
        echo "Must provide a cluster to clusterCollectCoverage" >&2
        exit 1
    fi
    local cluster="$1"
    if [ "$VmProvider" = "GCE" ]; then
        echo 2>&1 "clusterCollectCoverage not supported for $VmProvider"
        exit 1
    elif [ "$VmProvider" = "Azure" ]; then
        local host
        firsthost=true
        for host in $(getNodes "$cluster"); do
            echo "COVERAGE host: $host"
            if $firsthost; then
                dst_dir=${cvgRoot}/bin
                mkdir -p $dst_dir
                echo "COVERAGE binary dst_dir: $dst_dir"
                scp -B -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_azure azureuser@${host}:/opt/xcalar/bin/usrnode $dst_dir
                firsthost=false
            fi
            dst_dir=${cvgRoot}/${host}
            mkdir -p $dst_dir
            nodeSsh "$cluster" "$host" "ls -l /var/opt/xcalar/coverage"
            scp -r -B -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_azure "azureuser@${host}:/var/opt/xcalar/coverage" ${dst_dir}/
            mv ${dst_dir}/coverage ${dst_dir}/rawprof
            echo "COVERAGE raw profile dst_dir: ${dst_dir}/rawprof"
        done

    elif [ "$VmProvider" = "Ovirt" ]; then
        echo 2>&1 "clusterCollectCoverage not supported for $VmProvider"
        exit 1
    else
        echo 2>&1 "Unknown VmProvider $VmProvider"
        exit 1
    fi
}
