#!/bin/bash

set +e
sudo systemctl stop xcalar
sudo pkill -9 usrnode
sudo pkill -9 xcmonitor
sudo pkill -9 expServer
sudo pkill -9 chidnode
sudo pkill -9 xcmgmtd
set -e
