# clusterwise operations for VMs on Ovirt.
#
# Usage: ovirtcluster-ssh.sh --cluster clustername [--ssh sshcmd] [--list] [--verbose] [--help]
#
# Note: clustername supplied to required --cluster arg should be the
# basename of the cluster nodes.  i.e., if you have a cluster of nodes:
#    clustera-abc-vm0
#    clustera-abc-vm1
#    clustera-abc-vm2
# then specify: --clusteer clustera
#

set -e

# assumes OVIRT_UNAME and OVIRT_PASSWORD env vars have been set;
# tool will pause waiting for credentials otherwise!

if [ -z "$XLRINFRADIR" ]; then
    export XLRINFRADIR="$(cd $SCRIPTDIR/.. && pwd)"
fi
OVIRTTOOL_DOCKER_WRAPPER="$XLRINFRADIR/bin/ovirttool_docker_wrapper"
CLUSTER_NAME="" # gets set by --cluster option
# temp dir for files created during script execution
TMP_DIR="$(mktemp -d -t ovirtclusterXXXXXX)" || exit 1
trap "{ rm -r $TMP_DIR ; }" EXIT

# echo usage string to stderr
usage() {
    local script_name=$(basename "$0")
    local usagestr="
Usage: $script_name --cluster clustername [--ssh sshcmd] [--list] [--help]

    --cluster clustername
        cluster to do operations on
    --list
        list hostnames of all nodes in the cluster 'clustername'
    --verbose
        when --list specified: in addition to hostnames, also displays IP and status of each node
        THIS CAN TAKE MUCH LONGER, depending on number of VMs are on Ovirt.
    --ssh sshcmd
        send ssmcmd to all nodes in the cluster 'clustername'
        ENCAPSULATE IN QUOTES! i.e., --ssh 'echo hello'
    --help
        print this message and quit.
"
    echo "$usagestr" >&2
}

# create contents for a ssh_config file
# create a file which has settings so you can ssh non-interactively for trusted hosts
# prints contents to stdout
ssh_config_file_contents() {
    if [ -z "$1" ]; then
        echo "Must supply a hostname to ssh_config_file_contents" >&2
        exit 1
    fi
    echo "
Host $1
    HostName $1.int.xcalar.com
    ForwardAgent yes
    PubKeyAuthentication yes
    PasswordAuthentication no
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"
}

# send an ssh cmd to all nodes of a given cluster.
cluster_ssh() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Must specify cluster and sshcmd as 1,2 positional args to cluster_ssh" >&2
        exit 1
    fi
    # create an ssh_config file, holding info for each of the nodes in the cluster
    local ssh_config_file="$TMP_DIR/ssh_config"
    rm "$ssh_config_file" >/dev/null 2>&1 || true # rm if exists from previous run; appending during for loop
    local cluster_nodes=$(get_cluster_node_info "$1")
    echo "$cluster_nodes" | while read hostname; do
        local node_config=$(ssh_config_file_contents $hostname)
        echo "$node_config" >> "$ssh_config_file"
    done

    # send ssh cmds to each of the nodes, supplying the ssh_config file created
    echo "$cluster_nodes" | while read hostname; do
        echo "$2" | ssh -q -F "$ssh_config_file" jenkins@$hostname
    done
}

# prints line of data for each node in a cluster to stdout, one line per node
# -mandatory 1st arg: name of cluster
# - if optional 2nd arg passed, each data line contains hostname, ip, status (takes MUCH LONGER)
#   if no 2nd arg passed, each data line contains only hostname
# ex: suppose there's vms test1-vm0 and test1-vm1 in Ovirt,
# get_cluster_node_hostname test1 prints to stdout:
# test1-vm0
# test1-vm1
# get_cluster_node_hostname test1 verbose prints to stdout:
# test1-vm0 10.10.2.154 UP
# test1-vm1 10.10.2.155 DOWN
get_cluster_node_info() {
    if [ -z "$1" ]; then
        echo "Must specify cluster to get_cluster_node_info" >&2
        exit 1
    fi
    local list_arg="--list"
    if [ ! -z "$2" ]; then
        list_arg="$list_arg --verbose"
    fi
    local hostname_list=$("$OVIRTTOOL_DOCKER_WRAPPER" $list_arg | grep -v DEBUG | grep "^$1")
    # want to get return code so can fail if script fails, but also save output as local variable...
    echo "$hostname_list" | while read hostname; do
        local strip_carriage=$(echo "$hostname" | sed -e 's/\r//g')
        echo "$strip_carriage"
    done
}

# check a value obtained for a cmd arg to script is not empty
# usage: check_has_value <arg name> <value to check>
check_has_value() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Must specify <arg name> <value to check> as 1st and 2nd args to check_as_value" >&2
        exit 1
    fi
    local arg_name="$1"
    local check_val="$2"
    # checking -- because shifting to get arg values, if they didn't supply
    # could have got a next cmd args --a --b (--a should have a value)
    if [[ -z "$check_val" ]] || [[ "$check_val" == --* ]]; then
        echo "Must specify value to $arg_name" >&2
        exit 1
    fi
}

# check a given cmd param is present in script args
# usage: check_required <req arg> <list of args sent to bash script>
check_required() {
    if [ -z "$1" ]; then
        echo "Must specify cmd arg to check, to check_required" >&2
        exit 1
    fi
    local check_var="$1"
    shift
    if [[ "'$@'" != *"$check_var"* ]]; then
        echo "$check_var is required (see --help)" >&2
        exit 1
    fi
}

# get user cmd arg
# (save copy of script args so can check required args after; they'll shift out by then)
script_args="$@"
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --help)
            usage
            exit 0
            ;;
        --ssh)
            SSH_CMD="$1"
            check_has_value --ssh "$SSH_CMD"
            shift
            ;;
        --list)
            LIST=$cmd
            ;;
        --verbose)
            VERBOSE=$cmd
            ;;
        --cluster)
            CLUSTER_NAME="$1"
            check_has_value --cluster "$CLUSTER_NAME"
            shift
            ;;
  esac
done
# check required args (doing after so --help displays even if missing required args)
check_required --cluster "$script_args"
# make sure operations specified appropriately, then run request...
if [ -z "$LIST" ] && [ -z "$SSH_CMD" ]; then
    echo "Must specify at least one of the options: --list, or --ssh sshcmd" >&2
    exit 1
else
    if [ ! -z "$LIST" ] && [ ! -z "$SSH_CMD" ]; then
        echo "Specify one or the other, not both: --ssh, --list" >&2
        exit 1
    elif [ ! -z "$SSH_CMD" ] && [ ! -z "$VERBOSE" ]; then
        echo "--verbose option only works for --list (lists more data)" >&2
        exit 1
    else
        # run requested operation

        # list all nodes in the cluster
        if [ ! -z "$LIST" ]; then
            get_cluster_node_info "$CLUSTER_NAME" "$VERBOSE"
        fi

        # send ssh cmd to all nodes in the cluster
        if [ ! -z "$SSH_CMD" ]; then
            cluster_ssh "$CLUSTER_NAME" "$SSH_CMD"
        fi
    fi
fi
