#!/bin/bash

# usage:
# sudo bash fixCgroups.sh <USER>
# where <USER> is the user to set up cgroups for

USER=""
if [ -z "$1" ]; then
   echo "Must supply USER to set cgroups for as first argument to script" >&2
   exit 1
else
   USER="$1"
fi

cgroup_xcalar_sys_xpus=xcalar_sys_xpus_${USER}
cgroup_xcalar_usr_xpus=xcalar_usr_xpus_${USER}
cgroup_xcalar_xce=xcalar_xce_${USER}
cgroup_xcalar_mw=xcalar_middleware_${USER}

cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_sys_xpus}
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_sys_xpus}/sched0
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_sys_xpus}/sched1
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_sys_xpus}/sched2
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_usr_xpus}
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_usr_xpus}/sched0
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_usr_xpus}/sched1
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_usr_xpus}/sched2
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_xce}
cgcreate -t "$USER:$USER" -a "$USER:$USER" -g cpu,cpuacct,cpuset,memory:${cgroup_xcalar_mw} 
