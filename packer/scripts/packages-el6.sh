#!/bin/bash

yum erase -y 'ntp*'
yum install -y chrony
/etc/init.d/chrony restart
chkconfig chrony on
