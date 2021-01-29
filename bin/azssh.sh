#!/bin/bash
set -e

optUsername="azureuser"
optPrefix=""

usage()
{
    cat << EOF
    Creates a new tmux window with new panes (one per VM) that SSH to each VM.

    Must be run within tmux with proper ssh credentials

    Example:
        azssh.sh releaseteststart-demandpaging-11-vm

    Usage: $myName [options] <Cluster Prefix>
        -u <username>   username (default: $optUsername)
        -h              This help
EOF
}

launchPanes() {
    local numNodes=$(az vm list-ip-addresses -otable | grep $optPrefix | wc -l)

    local currVm=0
    local cmd="ssh $optUsername@${optPrefix}${currVm}.azure"
    local targetPane=$(tmux new-window -P "$cmd")

    for vm in $(seq 1 $(($numNodes - 1)) )
    do
        # Something about the tmux ordering requires us to reverse the
        # host ordering to get desired pane sequence
        currVm=$(($numNodes - $vm))
        cmd="ssh $optUsername@${optPrefix}${currVm}.azure"
        tmux split-window -t "$targetPane" "$cmd"
        tmux select-layout -t "$targetPane" tiled
    done

    tmux select-pane -t "$targetPane"
}

while getopts "hu:" opt; do
  case $opt in
      u) optUsername="$OPTARG";;
      *) usage; exit 0;;
  esac
done

if [[ ! "$TMUX" ]]
then
    echo "Requires running in tmux session. Try:"
    echo "    tmux new"
    echo "then rerun this command"
    exit 1
fi

if [ $# -eq 0 ]; then
   usage
   exit 0
fi

shift $(($OPTIND - 1))
optPrefix="$1"

launchPanes
