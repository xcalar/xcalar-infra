#!/usr/bin/env bash

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

# to make debug statements
#  debug "debug comment"
#  then run script as: `VERBOSE=1 ./local_installer.sh`
debug() {
    if [ "$VERBOSE" = 1 ]; then echo >&2 "debug: $@"; fi
}

SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STAGING_DIR="/tmp/xpestaging"
IMGID_FILE="$SCRIPT_DIR/../Data/.imgid"
XCALAR_IMAGE_REPO=xcalar_design
GRAFANA_IMAGE_REPO=grafana_graphite
XCALAR_CONTAINER=xcalar_design
GRAFANA_CONTAINER=grafana_graphite
# installer dirs created on the local machine
# these should remain even after installation complete, as long as they want XPE)
APPDATA="$HOME/Library/Application Support/Xcalar Design"
XPEDATA="$APPDATA/.sessions" # want data in here hidden in mac Finder
LOCALLOGDIR="$XPEDATA/Xcalar Logs" # will mount to /var/log/xcalar so logs persist through upgrades
LOCALXCEHOME="$XPEDATA/Xcalar Home" # will mount to XCALAR_ROOT so session data, etc. persissts through upgrde
XCALAR_ROOT="/var/opt/xcalar"
LIC_FILENAME=XcalarLic.key # name of file of uncompressed license
XCALAR_LIC_REL="xpeinstalledlic" # dir rel to XCALAR_ROOT where lic file will go
LOCALDATASETS="$APPDATA/sampleDatasets"

XCALARCTL_PATH="/opt/xcalar/bin/xcalarctl" # path in Docker container where xcalarctl is

MAINHOSTMNT="$HOME" # path in the Xcalar Docker container to mount user's $HOME dir to
# will set as Xcalar's Default Data Target path (it must be a path in the container where Xcalar running)
# this way when user opens file browser they will see contents of their $HOME dir (else will be default container root which won't make sense to user)

XEM_PORT_NUMBER=15000 # should be port # in xemconfig
# files that will be required for completing the installation process
XDPCE_TARBALL=xdpce.tar.gz
GRAFANA_TARBALL=grafana_graphite.tar.gz

# clear current container
# if user has changed its name; won't be removing that
# remove the latest images.
cmd_clear_containers() {
    cmd_ensure_docker_up
    debug "Remove old docker containers..."
    docker rm -fv "$XCALAR_CONTAINER" >/dev/null 2>&1 || true
    # only remove grafana container if you're going to install it
    if [ ! -z "$INSTALL_GRAFANA" ]; then
        docker rm -fv "$GRAFANA_CONTAINER" >/dev/null 2>&1 || true
    fi

    # short term: clear out container by the old name
    # (name of container changed; if someone installed when it was called xdpce,
    # that container won't get cleared up from above code, and install will end up
    # failing for port being in use)
    # don't keep this in long term because it'll add to install time.
    # but short term because everyone who's done a prev install will end up hitting this
    docker rm -fv xdpce >/dev/null 2>&1 || true

    # untag current
    docker rmi "$XCALAR_IMAGE_REPO":current || true
}

cmd_setup () {

    local cwd=$(pwd)

    debug "Create install dirs and unpack tar file for install"

    ## CREATE INSTALLER DIRS, move required files to final dest ##
    if [ -e "$STAGING_DIR" ]; then
        debug "staging dir exists already $STAGING_DIR"
        rm -r "$STAGING_DIR"
    fi
    mkdir -p "$STAGING_DIR"
    cd "$STAGING_DIR"

    # copy installer tarball to the staging dir and extract it there
    cp "$SCRIPT_DIR/installertarball.tar.gz" "$STAGING_DIR"
    tar xzf installertarball.tar.gz

    if [ -e ".caddyport" ]; then
        CADDY_PORT=$(cat .caddyport)
    fi

    mkdir -p "$LOCALXCEHOME/config"
    mkdir -p "$LOCALXCEHOME/$XCALAR_LIC_REL"
    mkdir -p "$LOCALLOGDIR"
    mkdir -p "$LOCALDATASETS"

    cp -R .ipython .jupyter jupyterNotebooks "$LOCALXCEHOME" # put these here in case of initial install, need them in xce home
    cp defaultAdmin.json "$LOCALXCEHOME/config"
    # untar the datasets and copy those in
    # do this from the staging dir.
    # because tarred dir and dirname in APPDATA are same
    # and don't want to overwrite the dir in APPDATA if it's there,
    # in case we've taken out sample datasets in a new build.
    # instead extract in staging area then copy all the contents over.
    # this way they get new datasets, updated existing ones, and keep their old ones
    tar xzf sampleDatasets.tar.gz --strip-components=1 -C "$LOCALDATASETS/"
    rm sampleDatasets.tar.gz

    cd "$cwd"
}

cmd_load_packed_images() {
    cmd_ensure_docker_up

    local cwd=$(pwd)

        ###  LOAD THE PACKED IMAGES AND START THE NEW CONTAINERS ##

    cd "$STAGING_DIR"

    debug "load the packed images"
    # if grafana supposed to be installed, make sure grafana tarball is here
    # else fail early
    if [ ! -z "$INSTALL_GRAFANA" ]; then
        if [ -e "$GRAFANA_TARBALL" ]; then
            gzip -dc "$GRAFANA_TARBALL" | docker load
        else
            echo "This build marked for Grafana install, but no Grafana image tar was included!" >&2
            exit 1
        fi
    fi

    # each xdpce tarball includes an image w/ 3 tags:
    # <image name>:current, <image name>:lastInstall, and <image name>:<build number>
    # When the new images are loaded, Docker will detect existing images named
    # <image name>:current and <image name>:lastInstall
    # and untag them, leaving the <build number> tag only from that previously installed image
    # (want to keep these previous images, with their build number tag only)
    # So make sure there is SOME unique identifying tag across installs,
    # if they are always same, the last 'untag' of a previously installed image
    # will leave it unnamed

    # naming/build tag CAUTION::
    # if you build more than one XPE app w/ an official release tag, for the same RC build,
    # and go through install on both those apps, this action will untag all 3
    # of the tags from the previous install resulting in <none>:<none> dangling image
    # (won't happen if re-installing same app, because images its loading have same id as ones currently loaded so won't actually load anything, and
    # won't happen with non-official release tag because 3rd tags would be unique between the two apps - Jenkins bld number)

    gzip -dc "$XDPCE_TARBALL" | docker load

    # dev check: ensure there is xpdce:lastInstall, and it is now the img id
    # associated with this installer, in case tag names change on build side
    cmd_compare_against_installer_img "$XCALAR_IMAGE_REPO":lastInstall

    cd "$cwd"

}

cmd_create_grafana() {
    cmd_ensure_docker_up

    debug "Create grafana container"

    # create the grafana container
    docker run -d \
    --restart unless-stopped \
    -p 8082:80 \
    -p 81:81 \
    -p 8125:8125/udp \
    -p 8126:8126 \
    -p 2003:2003  \
    --name "$GRAFANA_CONTAINER" \
    "$GRAFANA_IMAGE_REPO:latest"
}

# create xdpce container
#    1st arg: image to use (Defaults to <image name>:lastInstall)
#    2nd arg: ram (int in gb)
#    3rd arg: num cores
cmd_create_xdpce() {
    cmd_ensure_docker_up

    debug "create xcalar container"

    local container_image="${1:-$XCALAR_IMAGE_REPO:lastInstall}"
    local extraArgs=""
    if [[ ! -z "$2" ]]; then
        extraArgs="$extraArgs --memory=${2}g"
    fi
    if [[ ! -z "$3" ]]; then
        extraArgs="$extraArgs --cpus=${3}"
    fi
    # if there is grafana container hook it to it as additional arg
    # only do if set to install, in case they've an old grafana container
    # but this install is not including grafana
    if [ ! -z "$INSTALL_GRAFANA" ]; then
        if docker container inspect "$GRAFANA_CONTAINER" >/dev/null 2>&1; then
            # the link to Grafana breaks if you specify the container name as --link instead of this
            extraArgs="$extraArgs --link $GRAFANA_IMAGE_REPO:graphite"
        fi
    fi

    # create license file and add env var to let Xcalar know where it is
    if [[ ! -z "$4" ]]; then
        echo "$4" > "$LOCALXCEHOME/$XCALAR_LIC_REL/$LIC_FILENAME"
        extraArgs="$extraArgs -e XCE_LICENSEFILE=$XCALAR_ROOT/$XCALAR_LIC_REL/$LIC_FILENAME"
    fi

    # create the xdpce container
    docker run -d -t --user xcalar --cap-add=ALL --cap-drop=MKNOD \
    --restart unless-stopped \
    --security-opt seccomp:unconfined --ulimit core=0:0 \
    --ulimit nofile=64960 --ulimit nproc=140960:140960 \
    --ulimit memlock=-1:-1 --ulimit stack=-1:-1 --shm-size=10g \
    --memory-swappiness=10 -e IN_DOCKER=1 \
    -e XLRDIR=/opt/xcalar -e container=docker \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME":"$MAINHOSTMNT" \
    -e XCE_CUSTOM_DEFAULT_DATA_TARGET_PATH="$MAINHOSTMNT" \
    -v "$LOCALXCEHOME":"$XCALAR_ROOT" \
    -v "$LOCALLOGDIR":/var/log/xcalar \
    -p $XEM_PORT_NUMBER:15000 \
    --name "$XCALAR_CONTAINER" \
    -p 8818:"${CADDY_PORT:-443}" \
    $extraArgs $MNTARGS "$container_image" bash

    # tag the image as current
    # (this will clear out existing <image name>:current tag, if any)
    docker tag "$container_image" "$XCALAR_IMAGE_REPO":current
}

cmd_start_xcalar() {
    cmd_ensure_docker_up

    debug "Start xcalar service inside the docker"
    # entrypoint for xcalar startup only hitting on container restart; start xcalar the initial time
    docker exec --user xcalar "$XCALAR_CONTAINER" "$XCALARCTL_PATH" start
    cmd_xcalar_wait
}

cmd_stop_xcalar() {
    cmd_ensure_docker_up

    debug "Stop xcalar service inside the docker"
    # entrypoint for xcalar startup only hitting on container restart; start xcalar the initial time
    docker exec --user xcalar "$XCALAR_CONTAINER" "$XCALARCTL_PATH" stop
}

cmd_compare_against_installer_img() {
    cmd_ensure_docker_up
    local appImgSha
    if [ ! -f "$IMGID_FILE" ]; then
        echo "Can not find image sha file to compare against for verification! (Looking at: $IMGID_FILE)" >&2
        exit 1
    else
        appImgSha=$(cat "$IMGID_FILE")
    fi
    local imgname="$1"
    local imgid
    if ! imgid=$(docker image inspect "$imgname" -f '{{ .Id }}'); then
       echo "No image sha found for $imgname!" >&2
       exit 1
    fi
    if [ "$imgid" != "$appImgSha" ]; then
       echo "$imgname is not the image associated with this app" >&2
       exit 1
    fi
}

cmd_verify_install() {
    cmd_compare_against_installer_img "$XCALAR_IMAGE_REPO":current
}

cmd_cleanup() {
    debug "Cleanup and remove staging dir"
    rm -r "$STAGING_DIR"
}

# revert_xdpce <img id> to revert to
cmd_revert_xdpce() {
    cmd_ensure_docker_up

    local revert_img_id="$1" # new img id or sha
    if [[ -z "${revert_img_id// }" ]]; then  # checks only whitespace chars
        echo "you must supply a value to revert image id!" >&2
        exit 1
    fi

    # check if xdpce container exists in expected name
    if docker container inspect "$XCALAR_CONTAINER"; then
        # get SHA of image hosted by current xdpce container, if any
        local curr_img_sha=$(docker container inspect --format='{{.Image}}' "$XCALAR_CONTAINER")

        # compares sha to check if already hosting the requested img
        local revert_img_sha=$(docker image inspect --format='{{.Id}}' "$revert_img_id")

        if [[ "$curr_img_sha" == $revert_img_sha ]]; then
            debug "$revert_img_id already hosted by $XCALAR_CONTAINER - revert is unecessary!"
            exit 0
        fi

        # delete the container
        docker rm -fv "$XCALAR_CONTAINER"
    else
        debug "there is NOT a $XCALAR_CONTAINER container"
    fi

    # now call to create the new container
    cmd_create_xdpce "$revert_img_id"
}

# Remove any container with a exact match to a name or id
# the container does not need to be running
# @TODO: is this redundant?  Can you ever have more than one match?
cmd_remove_docker_containers() {
    if [ -z "$1" ]; then
        echo "You must supply a container to remove" >&2
        exit 1
    fi
    cmd_ensure_docker_up
    docker container inspect "$1" -f '{{ .Id }}' | xargs -I {} docker rm -fv {} || true
}

# given name of a Docker image repo, for each of the images
# having that name, remove all container associated with it and itself 
cmd_remove_docker_image_repo() {
    if [ -z "$1" ]; then
        echo "You must supply an image to remove" >&2
        exit 1
    fi
    cmd_ensure_docker_up
    # get ID of all Docker images in the repo; cleanly delete them
    # note: image w multiple tags will get duplicate entries since they will have same id
    docker images | awk '{ print $1,$3 }' | awk '$1 ~ /^'$1'$/ { print $2}' | while read line
    do
        if [ -n "$line" ]; then # getting some blank lines
            cmd_cleanly_delete_docker_image "$line"
        fi
    done
}

# Given a unique identifier for an image
# (short id, sha, or <image>:<tag>),
# delete containers hosting that image, and then the image itself
# will not fail if image does not exist
cmd_cleanly_delete_docker_image() {
    if [ -z "$1" ]; then
        echo "Must supply an image to remove (id, sha, or <image>:<tag>)" >&2
        exit 1
    fi

    cmd_ensure_docker_up

    # remove any containers (running or not) hosting this image
    docker ps -a -q --filter ancestor="$1" --format="{{.ID}}" | xargs -I {} docker rm -fv {} || true
    # remove the image itself
    # If you supplied an image ID - this will delete ALL images with that id (other taggged images)
    # If you supplied <img>:<tag>, it will delete ONLY that specific image (other tagged images on the same image id will remain)
    docker rmi -f "$1" || true
}

# nuke all the xdpce containers and images; optional $1 removes local xpe dir
cmd_nuke() {
    cmd_ensure_docker_up

    debug "Remove all the xdpce containers and images"
    cmd_remove_docker_containers "$XCALAR_CONTAINER"
    cmd_remove_docker_image_repo "$XCALAR_IMAGE_REPO"

    debug "Remove all grafana containers and images"
    cmd_remove_docker_containers "$GRAFANA_CONTAINER"
    cmd_remove_docker_image_repo "$GRAFANA_IMAGE_REPO"

    if [ ! -z "$1" ]; then
        debug "Remove all app data (specified full uninstall)"
        if [ -d "$APPDATA" ]; then
            rm -r "$APPDATA"
        fi
    fi
}

docker_up() {
    docker version >/dev/null 2>&1
}

docker_installed() {
    command -v docker >/dev/null 2>&1
}

xcalar_services_up() {
    # XD_URL Is being set by the app entrypoint
    if [ -z "$XD_URL" ]; then
        echo "No $XD_URL set!  (has app entrypoint changed?)" >&2
        exit 1
    fi
    # endpoint checks services are up and ready
    expServerServiceCheckEndpoint="$XD_URL/app/service/status"
    curl -kf "$expServerServiceCheckEndpoint"
}

# DOCKER UTILS # ##TODO: move in to own util file;
# and the installer functions above in their own file?

# optional arg 1: if true, do not start Docker daemon, just wait for it to come up
# optional arg 2: seconds to wait before timing out waiting for Docker to come up
cmd_ensure_docker_up() {
    local dontStartDocker="${1:-false}"
    if ! docker_up; then
        if [ "$dontStartDocker" != true ]; then
            cmd_docker_start
        fi
        cmd_docker_wait "$2"
    fi
}

# starts docker and waits to come up, unless env variable
# NODOCKERSTART is set
cmd_docker_start() {
    if [ ! -z "$NODOCKERSTART" ]; then
        echo "Will not start Docker - NODOCKERSTART env variable detected" >&2
    else
        open -a Docker.app
    fi
}

# optional arg: number of seconds to wait before timing out waiting for Docker to come up
cmd_docker_wait() {
    local timeout="${1:-120}"
    local remainingTime=$timeout
    local pauseTime=1
    until docker_up || [ "$remainingTime" -eq "0" ]; do
        debug "docker daemon not avaiable yet $remainingTime"
        sleep "$pauseTime"
        remainingTime=$((remainingTime - pauseTime))
    done

    if ! docker_up; then
        # timed out waiting for daemon to come up
        echo "Timed out after waiting $timeout seconds for Docker daemon to come up!" >&2
        exit 1
    fi
}

# wait for Xcalar services to come up
cmd_xcalar_wait() {
    local timeout="${1:-120}"
    local remainingTime="$timeout"
    local pauseTime=1
    while [ $remainingTime -gt 0 ]; do
        if xcalar_services_up; then
            return 0
        fi
        debug "Xcalar services not up yet... $remainingTime"
        sleep "$pauseTime"
        remainingTime=$((remainingTime - pauseTime))
    done
    echo "Timed out after waiting $timeout seconds for Xcalar services to come up! (is the Xcalar container up?  Is Xcalar set to start on container start?)" >&2
    exit 1
}

# bring up XD and Grafana Docker containers, optionally wait for the Xcalar
# services to come up once the containers have started.
cmd_bring_up_containers() {
    cmd_ensure_docker_up

    local waitForXcalar="${1:-true}"
    docker start "$XCALAR_CONTAINER"
    docker start "$GRAFANA_CONTAINER" || true
    # xcalar services will NOT be up yet.  If you run XD in nwjs before all services
    # are up, will get auth error due to Jupyter require conflict with nwjs require
    if [ "$waitForXcalar" == true ]; then
        cmd_xcalar_wait
    fi
}

command="$1"
shift
cmd_${command} "$@"
