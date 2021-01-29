#!/bin/bash

# Move the updates repo into sep file and disable

if grep -q '^\[updates\]' /etc/yum.repos.d/CentOS-Base.repo; then
    sed -n '/^\[updates/,/^$/p' /etc/yum.repos.d/CentOS-Base.repo >/etc/yum.repos.d/updates.repo
    sed -i '/^\[updates/,/^$/d' /etc/yum.repos.d/CentOS-Base.repo
fi
if test -e /etc/yum.repos.d/updates.repo; then
    sed -i '/enabled/d' /etc/yum.repos.d/updates.repo
    echo 'enabled=0' >>/etc/yum.repos.d/updates.repo
    sed -i '/^$/d' /etc/yum.repos.d/updates.repo
fi
