#!/bin/bash

if [ -z $WORKSPACE ]; then
	echo "WORKSPACE not defined!"
	exit 1
fi

if [ -z $XLRINFRADIR ]; then
	echo "XLRINFRADIR not defined!"
	exit 1
fi

if [ -z $GRAFANA_DIR ]; then
	echo "GRAFANA_DIR not defined!"
	exit 1
fi

if [ -z $BUILD_DIRECTORY ]; then
	echo "BUILD_DIRECTORY not defined!"
	exit 1
fi

if [ -z $BUILD_NUMBER ]; then
	echo "BUILD_NUMBER not defined!"
	exit 1
fi

if [ -z $PATH_TO_XDP_INSTALLER ]; then
	echo "PATH_TO_XDP_INSTALLER not defined!"
	exit 1
fi

if [ -z $CONFIG_FILE_TO_COPY ]; then
	echo "CONFIG_FILE_TO_COPY not defined!"
	exit 1
fi

cd $WORKSPACE/$XLRINFRADIR/docker/xdpce/

make docker-image INSTALLER_PATH=$PATH_TO_XDP_INSTALLER

cp $WORKSPACE/$XLRINFRADIR/docker/xdpce/xdpce.tar.gz $WORKSPACE/$GRAFANA_DIR/
cp $WORKSPACE/$XLRINFRADIR/docker/xdpce/$CONFIG_FILE_TO_COPY $WORKSPACE/$GRAFANA_DIR/xem.cfg

cd $WORKSPACE/$GRAFANA_DIR

make

mkdir -p $BUILD_DIRECTORY/$BUILD_NUMBER

# fix the name of this installer in the make file and here
cp grafana_graphite-installer.sh $BUILD_DIRECTORY/$BUILD_NUMBER/

ln -sfn $BUILD_NUMBER $BUILD_DIRECTORY/lastSuccessful
