#!/bin/bash

set -e

###########
#
#  ./e2einstall.sh installerurl node-ip [True|False]
#	(if True will start up Xcalar at end)
#   Assumes Xcalar license file XcalarLic.key exists in same dir the shell script lives in
#
###########
DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

# install xcalar:
# get the requested CLI installer from netstore, and kick off the installation
# remove some yum repos first to clean things up
curl "$1" -o $DIR/installer.sh

rm -f /etc/yum.repos.d/epel*.repo /etc/yum.repos.d/mapr.repo /etc/yum.repos.d/nodesource.repo /etc/yum.repos.d/sbt.repo /etc/yum.repos.d/draios.repo /etc/yum.repos.d/ius.repo /etc/yum.repos.d/azure-cli.repo

/bin/bash $DIR/installer.sh --nostart --caddy --startonboot

# copy in the license files
echo 'copy lic files in to xcalar' >&2
cp $DIR/XcalarLic.key /etc/xcalar/XcalarLic.key

# generate config file.
# if you passed only one node (single node cluster - use localhost)
# multiple nodes passed put that node list
echo 'generate config file via templatehelper.sh' >&2

/bin/bash -e $DIR/templatehelper.sh $2

