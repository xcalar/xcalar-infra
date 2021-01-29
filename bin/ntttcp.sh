#!/bin/bash
#
# This script will ssh into the specified host, download
# ntttcp, a network testing program, and run it in a tmux
# session in server mode. The script then uses the same tool
# to connect to the remote ntttcp server and run a test.
# When the test terminates locally (or you interrupt it),
# the remote ntttcp program will also exit and quit the tmux
# session.
#
# While the benchmark is running, connect to the remote host
# in a different window and execute `tmux at -d -t mysession`
# to view the remote program running. Do detach, press C-b d
# (Control-b <release> d), or C-b d short.

_ssh() {
    ssh "$@"
}

# Network testing program
NTTTCP=http://repo.xcalar.net/deps/ntttcp-1.4.0.tar.gz

# The vm to connect to (remote hostname) and remote port, and remote ip.
vm="${1:-vm1}"
port=${2:-6001}
ip=$(getent hosts $vm | awk '{print $1}') || exit 1
myip=$(hostname -i)

# find out what the network interface is called on the remote and local sides. we need
# to pass this to ntttcp. (eg, eth0, ensp30, etc). We do this by getting the route
# back to us and parsing the ip route output.
remote_nic=$(_ssh $vm /sbin/ip route get $myip | head -1 | awk '{print $3}')
local_nic=$(/sbin/ip route get $ip | head -1 | awk '{print $3}')

echo "Remote: IP: $ip       Nic: $remote_nic"
echo "Local:  IP: $myip     Nic: $local_nic"

# Make sure we can connect, and accept any host keys. Also
# check for tmux
_ssh $vm bash -c 'command -v tmux'

# Download the tool locally if we don't already have it
if ! test -e /tmp/ntttcp; then
   curl -fsSL $NTTTCP | tar zxf - -C /tmp
   chmod +x /tmp/ntttcp
fi

# Download tool on the remote side
if ! _ssh $vm test -e /tmp/ntttcp; then
	cat <<-EOF | _ssh $vm
	curl -fsSL $NTTTCP | tar zxf - -C /tmp
	chmod +x /tmp/ntttcp
	EOF
fi

# Kill any previous tmux session on $vm called mysession. The || true here is to cover for
# the fact if there's no session
_ssh $vm tmux kill-session -t mysession 2>/dev/null || true

# SSH back into $vm and start a new session called (-s) mysession. In this session run a single
# command, then detach (-d). We run the /tmp/ntttcp command that we downloaded earlier in the
# script. This runs ntttcp in server mode while it waits for connections. It runs once, meaning
# it accepts a connection from another ntttcp, runs the perf benchmark, then exits. With that
# tmux exits as well, and we'll be left with no more session - which is what we want in this case.
_ssh $vm tmux new-session -d -s mysession /tmp/ntttcp -r -m 8,0,$ip --show-tcp-retrans --show-nic-packets $remote_nic --show-dev-interrupts mlx4 -V -p $port || exit 1

sleep 3

/tmp/ntttcp -s $ip --show-tcp-retrans --show-nic-packets $local_nic --show-dev-interrupts mlx4 -V -p $port
rc=$?

# In case something went wrong, kill the remote session
_ssh $vm tmux kill-session -t mysession 2>/dev/null || true

exit $rc
