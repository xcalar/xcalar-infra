#!/bin/bash

# INSTALL:
#        bash <script path>/local_installer.sh
#
# UNINSTALL:
#        (backs up and removes existing install directory and removes containers)
#        bash <script path>/local_installer.sh uninstall
#
# EFFECT OF RUNNING THIS SCRIPT:
#
# When you run this script in dir with required files,
# any previous xdpce and grafana containers will be destroyed.
# it will create two docker containers (one for Grafana/graphite
# one for XEM cluster), and load the saved images for Grafana and XCE cluster
# included in the tarball, in to those containers.
# Grafana and XCE will be configured to communiicate automatically for stats collection.
#
set -e

xdpceRam=$1
xdpceCores=$2
grafana=$3

# to make debug statements
#  debug "debug comment"
#  then run script as: `VERBOSE=1 ./local_installer.sh`
debug() {
    if [ "$VERBOSE" = 1 ]; then echo >&2 "debug: $@"; fi
}

XCALAR_IMAGE=xdpce
GRAFANA_IMAGE=grafana_graphite
XCALAR_CONTAINER_NAME=xdpce
GRAFANA_CONTAINER_NAME=grafana_graphite

# files that will be required for completing the installation process
XDPCE_TARBALL=xdpce.tar.gz
GRAFANA_TARBALL=grafana_graphite.tar.gz

# if you want grafana, make sure there's the grafana tar in this
if [ $grafana == 'true' ]; then
	if [ ! -e "$GRAFANA_TARBALL" ]; then
		echo "Trying to run with a Grafana installation.  but no grafana tarball found in installer."
		exit 1
	fi
fi

clear_containers() {

    debug "Remove old docker containers..."
    docker rm -f $XCALAR_CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm -f $GRAFANA_CONTAINER_NAME >/dev/null 2>&1 || true

}

            ## SETUP ##

# installer dirs created on the local machine
# these should remain even after installation complete, as long as they want XPE)
XPEDIR="/Applications/XcalarPersonalEdition.app/Contents/xpebin"
XPEIMPORTS="$XPEDIR/imports" # dedicated dir where user can map datasets, etc. for access in Xcalar
LOCALLOGDIR="$XPEDIR/xceLogs" # will mount to /var/log/xcalar so logs persist through upgrades
LOCALXCEHOME="$XPEDIR/xceHome" # will mount /var/opt/xcalar here so session data, etc. persissts through upgrde
XPEBIN="$XPEDIR/bin"

XEM_PORT_NUMBER=15000 # should be port # in xemconfig

## @TODO:
## prior to clearing container:
## BACKUP EXISTING DATA (XPEDIR and curr docker images for containers)
## so if upgrading and upgrade does not succeed, can go back to previous state
clear_containers

        ##  UNINSTALL OPTION ##

# if user running this as an uninstall, back up contents before deleting the dir
if [ "$1" == uninstall ]; then

    if [ -d $XPEDIR ]; then
        BACKUPDIR="$HOME/xpe_backup_$(date +%F_%T)"
        debug "mv $XPEDIR to $BACKUPDIR"
        mv $XPEDIR $BACKUPDIR
        addmsg=" A backup of previous install data, can be found at $BACKUPDIR"
    fi

    echo "XPE has been uninstalled. $addmsg" >&2
    exit 0
fi

    ## CREATE INSTALLER DIRS, move required files to final dest ##

# make the default user installation dirs
mkdir -p "$XPEIMPORTS"
mkdir -p "$LOCALLOGDIR"
mkdir -p "$LOCALXCEHOME"
mkdir -p "$LOCALXCEHOME/config"
mkdir -p "$XPEBIN"

# create tmp staging dir for extracting the installation contents
# move the tarball there and extract it
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STAGING_DIR=`mktemp -d 2>/dev/null || mktemp -d -t 'xpeinstaller'` # creates tmp dir on osx and linux
cd $STAGING_DIR

echo "Copy tar file.. to staging dir $STAGING_DIR (if over netstore could take some time...)" >&2
cp "$DIR/installpack.tar.gz" .
tar -xzf installpack.tar.gz

cp -R .ipython .jupyter jupyterNotebooks "$LOCALXCEHOME" # put these here in case of initial install, need them in xce home
cp -R xcalar-gui "$XPEDIR"
cp defaultAdmin.json "$LOCALXCEHOME/config"
cp .imgid getimgid.sh "$XPEBIN"
    ###  LOAD THE PACKED IMAGES AND START THE NEW CONTAINERS ##

# each load, will have 2 versions of the image:
# xdpce:latest and xdpce:<build number> (same for grafana-graphite)
# want to keep previous install images, but only need one - the xdpce:<old build number>
# (if you specify 'rmi image' without a tag, will remove image:latest)
# also if you do not do this, when you load the new images in the tar
# (xdpce:latest and xdpce:<new build number>, and similar for grafana-graphite)
# will detect existing xdpce:latest (the one from the old build),
# and rename it to an unnamed image (keeping the xdpce:<old buld> as well)
debug "rmi xdpce:latest and grafana-graphite:latest"
docker rmi -f $XCALAR_IMAGE || true
docker rmi -f $GRAFANA_IMAGE || true

if [ $grafana == 'true' ]; then
	debug "load grafana image and make container"
	gzip -dc "$GRAFANA_TARBALL" | docker load -q

	# create the grafana container
	run_cmd="docker run -d \
	--restart unless-stopped \
	-p 8082:80 \
	-p 81:81 \
	-p 8125:8125/udp \
	-p 8126:8126 \
	-p 2003:2003  \
	--name $GRAFANA_CONTAINER_NAME \
	$GRAFANA_IMAGE"
	debug "Docker run cmd: $run_cmd"
	$run_cmd

	# create link arg to this when you make xdpce container
	xdpcelinks="--link $GRAFANA_IMAGE:graphite"
fi

# always make xdpce container
debug "load packed xdpce image and make xdpce container"
gzip -dc "$XDPCE_TARBALL" | docker load -q
run_cmd="docker run -d -t --user xcalar --cap-add=ALL --cap-drop=MKNOD \
--restart unless-stopped \
--security-opt seccomp:unconfined --ulimit core=0:0 \
--ulimit nofile=64960 --ulimit nproc=140960:140960 \
--ulimit memlock=-1:-1 --ulimit stack=-1:-1 --shm-size=10g \
--memory-swappiness=10 -e IN_DOCKER=1 \
-e XLRDIR=/opt/xcalar -e container=docker \
-v /var/run/docker.sock:/var/run/docker.sock \
-v $LOCALXCEHOME:/var/opt/xcalar \
-v $LOCALLOGDIR:/var/log/xcalar \
-v $XPEIMPORTS:/mnt/imports2 \
-p $XEM_PORT_NUMBER:15000 \
--name $XCALAR_CONTAINER_NAME \
-p 8080:8080 -p 443:443 -p 5000:5000 \
-p 9090:9090 -p 8889:8889 \
-p 12124:12124 -p 18552:18552 $xdpcelinks $XCALAR_IMAGE bash"
debug "Docker run cmd: $run_cmd"
$run_cmd
wait
# entrypoint for xcalar startup only hitting on container restart; start xcalar the initial time
docker exec -it --user xcalar $XCALAR_IMAGE /opt/xcalar/bin/xcalarctl start

# go back to script dir and delete stging dir
cd "$DIR"
debug "remove staging dir: $STAGING_DIR"
rm -r "$STAGING_DIR"
