#!/bin/bash

# Kill all of the old processes
pgrep -u `whoami` lt-usrnode | xargs kill -9
pgrep -u `whoami` xcmgmtd | xargs kill -9

# Sleep for a random amoutn of time before polling git so we don't DDOS the git server
number=$RANDOM
let "number %= 3"
sleep $number
