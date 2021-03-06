#!/bin/bash

# to be called by Jenkins job 'XcalarPersonalEditionBuilder'
# job calls <infra>/jenkins/XcalarPersonalEditionBuilder.sh which does setup,
# and then calls this script.

set -e

# Jenkins job params, or env vars exported by setup script <infra>/jenkins/XcalarPersonalEditionBuilder.sh)
# check here in case Jenkins job config changes
: "${XLRGUIDIR:?Need non-empty env var XLRGUIDIR}" # exported by setup script
: "${XLRINFRADIR:?Need non-empty env var XLRINFRADIR}" # ''
# trick: if you want to run this script locally but don't have a graphite git repo,
# supply any value for this env var, and export BUILD_GRAFANA=false; it'll never use the dir then
: "${GRAFANADIR:?Need non-empty env var GRAFANADIR}"
: "${BUILD_DIRECTORY:?Need to set non-empty env var BUILD_DIRECTORY}" # here down Jenkins params
: "${BUILD_NUMBER:?Need to set non-empty env var BUILD_NUMBER}"
: "${PATH_TO_XCALAR_INSTALLER:?Need to set netstore rpm installer path as PATH_TO_XCALAR_INSTALLER)}"
: "${CADDY_PORT:?Need non-empty env var CADDY_PORT}"
: "${BUILD_GRAFANA:?Need non-empty env var BUILD_GRAFANA}"
: "${DEV_BUILD:?Need non-empty env var DEV_BUILD}"
: "${OFFICIAL_RELEASE:?Need non-empty env var OFFICIAL_RELEASE}"
: "${IGNORE_VERSION_MISMATCH:?Need non-empty env var IGNORE_VERSION_MISMATCH}"
: "${APP_NAME:?Need non-empty env var APP_NAME}"

# vars Makefile will use
export XCALAR_IMAGE_NAME="${XCALAR_IMAGE_NAME:-xcalar_design}"
export XCALAR_CONTAINER_NAME="${XCALAR_CONTAINER_NAME:-xcalar_design}"
export XPE=true

INFRA_XPE_DIR="$XLRINFRADIR/docker/xpe"
BASH_HELPER_FUNCS="$INFRA_XPE_DIR/scripts/local_installer_mac.sh"
# the xcalar-gui build that XD (in Docker) and app (out of Docker, for installer,
# uninstaller, etc.) will use. if not passed, build_xcalar_gui_for_app function
# will build from xcalar-gui repo and set this variable.
# THIS DIRECTORY WILL BE MODIFIED (xpeServer will be built in it, etc.).
CUSTOM_XPE_GUI_BUILD="${CUSTOM_XPE_GUI_BUILD:-""}"
XPE_BUILD_TARGET_DIR="xcalar-desktop-edition" # name of xcalar-gui build dir generated by grunt --product=XPE
APP_TARFILE="${APP_TARFILE:-"$APP_NAME.tar.gz"}" # name of final tarred app that ends up in bld

# some app metadata and build files require the app's name;
# those files have a common placeholder value where name should be. will sed
# placeholder to the app basename (will make it easier to change app name)
# this is that placeholder (see staticfiles/Info.plist for an example of the placeholder)
BASENAME_PLACEHOLDER="@PLACEHOLDER_APPNAME@"

INSTALLERTARFILE=installertarball.tar.gz # name for tarball containing docker images, dependencies, etc.

DRAG_AND_DROP_MSG="" # will display msg explaining how to create drag and drop dmg post-build
# will get set if build was successful and print as last step in exit trap so its last thing displayed in console log

### CREATE STAGING DIR TO DO BUILDING IN ###
STAGING_DIR="$(mktemp -d --tmpdir xpeBldStagingXXXXXX)"

###  CLEAENUP/HELPER FUNCTIONS ###

# removes xcalar and grafana Docker artefacts. to run at job start and cleanup.
# clear xcalar repo entirely; don't want to cache
# (mostly in case xdpce Dockerfile changes in future to incorporate src code checkout as part of its bld
# which wouldn't want to cache; the build time it saves from using cache is about < 1 min so not worth this risk...)
clear_docker_artefacts() {
    # try to remove expected container in case not associated w image
    # (if it is associated w the image, remove_docker_image_repo will run much faster if you give this cmd first)
    docker rm -fv "$XCALAR_CONTAINER_NAME" || true
    "$BASH_HELPER_FUNCS" remove_docker_image_repo "$XCALAR_IMAGE_NAME"
    # only remove grafana container, not image; keep in cache so won't need to rebuild
    docker rm -fv grafana_graphite || true
}

# removes build specific artefacts which require context of this run (for cleanup)
removeBuildArtefacts() {
    docker kill "$XCALAR_CONTAINER_NAME" || true # use kill because it's quicker than rm and Jenkins abort cleanup has limited time
    docker rmi -f grafana_graphite:"$BUILD_NUMBER" || true
}

cleanup() {
    # if you are running through Jenkins - if the job fails or completes, this entire function will run
    # but if aborted, there are only a couple seconds before shell is terminated
    # therefore prioritize cleaning up objects which could interfere w future runs or other jobs using this machine
    rm -r "$STAGING_DIR"
    removeBuildArtefacts
    clear_docker_artefacts
    echo "$DRAG_AND_DROP_MSG"
}

# builds the xcalar-gui project in the state required by the app to be in the Docker container
# (builds from XLRGUIDIR if build does not exist)
# (RPM installers will install xcalar-gui build with standard build targets; for xcalar-gui
# to work in the app needs to be built with --product=XPE option)
build_xcalar_gui_for_app() {

    # CUSTOM_XPE_GUI_BUILD is an env var that can be set before job runs to point to a gui build to use.
    # if it wasn't set build one
    if [ ! -d "$CUSTOM_XPE_GUI_BUILD" ]; then
        cd "$XLRGUIDIR"
        git submodule update --init >&2
        git submodule update >&2
        npm install --save-dev >&2
        node_modules/grunt/bin/grunt init >&2
        # gui build will give a default "Xcalr Desktop Edition" branding when
        # --product=XPE but specify branding in case
        node_modules/grunt/bin/grunt dev --product=XPE --branding="$APP_NAME" >&2
        # make sure expected target exists
        if [ ! -d "$XPE_BUILD_TARGET_DIR" ]; then
            echo "Gui build target $XPE_BUILD_TARGET_DIR does not exist in $XLRGUIDIR after building (has target name changed?)" >&2
            exit 1
        else
            cd "$XPE_BUILD_TARGET_DIR"
            CUSTOM_XPE_GUI_BUILD=$(pwd)
        fi
    fi

    # do follow up tasks required for gui build to work in app,
    # regardless if custom build was specified
    # or built by job

    # build the xpe server
    cd "$CUSTOM_XPE_GUI_BUILD/services/xpeServer"
    npm install >&2

    # modify GUI code to ignore version mismatch, if requested
    if "$IGNORE_VERSION_MISMATCH"; then
        sed -i 's/versionMatch\s*=\s*false/versionMatch = true/g' ${CUSTOM_XPE_GUI_BUILD}/assets/js/shared/setup/xvm.js
    fi
}

# create installer tarball to be packaged in the app (tarball with
# the files needed during app install-time on host) by generating all the
# required assets including the saved Docker images.
# saves the tarball in the staging dir.
generate_installer_tarball()  {

    cd "$STAGING_DIR"

    echo "Create installer tarball for app " >&2

    # - create tmp dir.
    # - shift all the installer assets in to tmp dir.
    # - tar tmp dir at end of function as the installer tarball.
    # DIR STRUCTURE IN TARBALL IS IMPORTANT.
    # local_installer_mac.sh functions (which handle installing the app on a Mac)
    # look for assets in specific locations.

    local dir_to_tar_name="tarfiles"
    mkdir -p "$dir_to_tar_name"
    # get full path so know where to copy files in to
    cd "$dir_to_tar_name"
    local dir_to_tar
    dir_to_tar=$(pwd)
    cd "$STAGING_DIR"

    # build the grafana-graphite container if requested.
    # (BUILD_GRAFANA is a boolean arg in the Jenkins job)
    if [ "$BUILD_GRAFANA" = true ]; then
        cd $GRAFANADIR
        make grafanatar
        # it will have saved an image of the grafana container
        # add saved image to dir for installer tarball
        cp grafana_graphite.tar.gz "$dir_to_tar"
    fi

    # build xdpce container
    # (do not actually need any port exposed since just need the image, so do not expose any port when blding
    # just to reduce chances of port conflicts on this machine if the container gets left over somehow)
    cd "$XLRINFRADIR/docker/xdpce"
    make docker-image INSTALLER_PATH="$PATH_TO_XCALAR_INSTALLER" CONTAINER_NAME="$XCALAR_CONTAINER_NAME" CONTAINER_IMAGE="$XCALAR_IMAGE_NAME" PORT_MAPPING="" CUSTOM_GUI="$CUSTOM_XPE_GUI_BUILD"

    # make will save an image of the container (xdpce.tar.gz),
    # and also copies of dirs saved in 'xcalar home'.
    # these dirs are needed on the host at app install time, if you map local
    # volumes to them (as this mapping will overwrite what's saved in the
    # image, so need these as defaults for initial installs)
    # - move these dirs to be included in the installer tarball
    mv .ipython "$dir_to_tar"
    mv .jupyter "$dir_to_tar"
    mv jupyterNotebooks "$dir_to_tar"
    mv xdpce.tar.gz "$dir_to_tar"
    # make also saves a copy of the xcalar-gui dir that got installed in the
    # Docker container; move to staging dir to be consumed by make-app.sh
    # (this should NOT be part of installer tarball; its just a byproduct of
    # generating the installer tarball assets so dealing with it here)
    mv xcalar-gui "$STAGING_DIR"

    # copy in defaultAdmin from the infra repo, for installer tarball
    cp "$XLRINFRADIR/docker/xdpce/defaultAdmin.json" "$dir_to_tar"

    # set caddy port as a text file, so host side will know which Caddyport to use
    echo "$CADDY_PORT" > "$dir_to_tar/.caddyport"

    # download sample datasets for the installer tarball
    # (they will be saved locally on the host installing the app,
    # and mapped in to the container created on that host.)
    cd "$dir_to_tar"
    curl -f -L http://repo.xcalar.net/deps/sampleDatasets.tar.gz -O

    # create the installer tarball with the assets gathered
    cd "$STAGING_DIR"
    tar -czf "$INSTALLERTARFILE" -C "$dir_to_tar" .
}

write_build_metadata() {
    # write out a file with build info
    cat > "$FINALDEST/BLDINFO.txt" <<EOF
PATH_TO_XCALAR_INSTALLER=$PATH_TO_XCALAR_INSTALLER
OFFICIAL_RELEASE=$OFFICIAL_RELEASE
DEV_BUILD=$DEV_BUILD
BUILD_GRAFANA=$BUILD_GRAFANA
EOF
}

# generates the .app, tars it, and put that tarfile in final build dest
build_app() {
    # generate installer tarball and other assets needed for app
    generate_installer_tarball

    echo "making mac app..." >&2
    # create the app; make-app.sh will create installer, uninstaller from GUI build.
    # need whichever xcalar-gui created here so branding will be same.
    # (generate_installer_tarball generates the tarball passed to INSTALLERTARBALL arg)
    APPOUT="$STAGING_DIR/$APP_NAME.app" GUIBUILD="$CUSTOM_XPE_GUI_BUILD" INSTALLERTARBALL="$STAGING_DIR/$INSTALLERTARFILE" bash -x "$INFRA_XPE_DIR/scripts/make-app.sh"

    # set app name occurances before tarring app
    set_app_name "$STAGING_DIR/$APP_NAME.app"

    # tar the app
    # (will need to be downloaded from Mac, but nwjs binaries
    # are not world readbale)
    tar -czf "$APP_TARFILE" "$APP_NAME.app"

    # copy to build directory
    # (building app in staging dir instead of directly in to build because most likely the
    # build dir is remotely on netstore, want all work to be done exclusively on the
    # jenkins slave then copy it in only when everything complete)
    cp -r "$APP_TARFILE" "$FINALDEST"
}

# the drag and drop dmg for the app, is created post-build from a Mac.
# there is a script which creates the dmg.
# copy in that script and its dependencies to final build, and take note of way
# to call the script specifically for this build, so can display it to user at
# end of build
setup_files_for_drag_and_drop_dmg() {
    dmgCreatorDir="dragAndDropDmgFiles"
    # copy in creator script and dependencies
    cp -r "$INFRA_XPE_DIR/$dmgCreatorDir" "$FINALDEST"
}

# swaps any occurance of @PLACEHOLDER_APPNAME@ in any files (recursively)
# in a given directory, with app's name.
# -- there are several files (app metadata such as Info.plist, nwjs'
# package.json, the .json the drag and drop tool uses, etc.) which
# need the app's name hardcoded.
# all these files have all been given a similar placeholder value,
# for where the app name should be.
# find all occurances of that placeholder value for the entire build now that
# it's complete, and swap all occurrances of the placeholder, with the app's name
set_app_name() {
    find "$1" -type f -print0 | xargs -0 sed -i s/"$BASENAME_PLACEHOLDER"/"$APP_NAME"/g
}

trap cleanup EXIT SIGTERM SIGINT # Jenkins sends SIGTERM on abort

### START JOB ###

FINALDEST="$BUILD_DIRECTORY/$BUILD_NUMBER"
mkdir -p "$FINALDEST"

cd "$STAGING_DIR"

clear_docker_artefacts
write_build_metadata
build_xcalar_gui_for_app
build_app
setup_files_for_drag_and_drop_dmg
set_app_name "$FINALDEST" # set_app_name already ran on the generated .app before it was tarred. this is handling any non-app files in the build (like drag and drop dmg files)

# symlink to this bld
cd "$BUILD_DIRECTORY" && ln -sfn "$BUILD_NUMBER" lastSuccessful

# msg of summary with instructions for creating a dmg using the script generated
# will print as last step in trap so its last thing printed
DRAG_AND_DROP_MSG="
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

 YOUR APP HAS BEEN GENERATED!!
 THE FULL APP IS STORED IN THIS TARFILE:

    $FINALDEST/$APP_TARFILE

 TO CREATE THE DRAG-AND-DROP DMG FOR THIS APP,
 RUN THE FOLLOWING BASH SCRIPT FROM ANY MAC WHICH
 HAS NETSTORE MOUNTED:
 (note: the script will assume netstore is mounted
 at '/netstore')

 APPTAR=\"$FINALDEST/$APP_TARFILE\" OUTPATH=\"/netstore/xpe_dmgs/$BUILD_NUMBER/$APP_NAME.dmg\" bash $FINALDEST/$dmgCreatorDir/createDragAndDropDmg.sh

 (the script will generate the dmg and store it on
  netstore; it will inform you of the dmg's
  final location)

=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
" >&2

# (staging dir removed in cleanup, which is called on normal exit)
