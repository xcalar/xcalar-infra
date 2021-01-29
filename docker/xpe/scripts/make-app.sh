#!/usr/bin/env bash

# Constructs the Xcalar Design app
# Mac app is just directory with specific directory structure; creates that and
# adds in all required files the app needs to run on the host.

set -e

: "${XLRINFRADIR:?Need to set non-empty XLRINFRADIR}"
: "${GUIBUILD:?Need to set non-empty GUIBUILD (path to built gui to include in app)}"
: "${BUILD_GRAFANA:?Need to set true or false env var BUILD_GRAFANA}"
: "${DEV_BUILD:?Need to set true or false env var DEV_BUILD}"
: "${XCALAR_IMAGE_NAME:?Need to set name of Docker image for .imgid app file, as env var XCALAR_IMAGE_NAME}"
: "${APPOUT:?Need to set non-empty APPOUT (path to app to generate)}"
: "${INSTALLERTARBALL:?Need to set non-empty INSTALLERTARBALL (path to installer tarball)}"

startCwd=$(pwd)

# make sure app out specified is .app
if [[ ! $APPOUT == *.app ]]; then
    echo "APPOUT must end in .app" >&2
    exit 1
fi
# create app; get basename and full path
if [ -e "$APPOUT" ]; then
    echo "$APPOUT already exists!" >&2
    exit 1
fi
APPBASENAME=$(basename "$APPOUT" .app)
mkdir -p "$APPOUT"
cd "$APPOUT"
APP_ABS_PATH=$(pwd)
cd "$startCwd"

XPEINFRAROOT="$XLRINFRADIR/docker/xpe"

# dir structure within app
CONTENTS="$APP_ABS_PATH/Contents"
MACOSDIR="$CONTENTS/MacOS"
LOGS="$CONTENTS/Logs"
RESOURCES="$CONTENTS/Resources"
BIN="$RESOURCES/Bin"
NWJSROOT="$RESOURCES/nwjs_root" # root nwjs manifest here
SERVERROOT="$RESOURCES/server"
SCRIPTS="$RESOURCES/scripts"
DATA="$RESOURCES/Data"
INSTALLER="$RESOURCES/Installer"

# nwjs to curl and include
# IF YOU CHANGE THIS - make sure you update app executable, <infra>/docker/xpe/scripts/Xcalar\ Design
NWJS_URL="http://repo.xcalar.net/deps/nwjs-sdk-v0.29.3-osx-x64.zip"
# nodejs to curl and include
# IF YOU CHANGE THIS - make sure you update app executable, <infra>/docker/xpe/scripts/Xcalar\ Design
NODE_URL="http://repo.xcalar.net/deps/node-v8.11.1-darwin-x64.tar.gz"

# icon to use for the app (must be a .icns file; see general MacOS app icon guidelines)
APPICON_PATH="$GUIBUILD/assets/images/appIcons/AppIcon.icns"

# MacOS apps require a certain structure in the app dir.
# create that here along with other dirs needed specifically for this app
create_app_structure() {
    mkdir -p "$CONTENTS"
    mkdir -p "$MACOSDIR"
    mkdir -p "$LOGS"
    mkdir -p "$RESOURCES"
    mkdir -p "$SERVERROOT"
    mkdir -p "$BIN"
    mkdir -p "$NWJSROOT"
    mkdir -p "$SCRIPTS"
    mkdir -p "$DATA"
    mkdir -p "$INSTALLER"
}

# MacOS apps require certain metadata; add that essential metadata here
setup_required_app_files() {
    # app essential metadata
    cp "$XPEINFRAROOT/staticfiles/Info.plist" "$CONTENTS"

    # add app entrypoint (executable file in 'MacOS' dir which gets run when user
    # double clicks app); must make exeuctable
    # executable MUST be same name as appbase name (mac requirement)
    cp "$XPEINFRAROOT/scripts/XPE_MAIN_EXECUTABLE" "$MACOSDIR/$APPBASENAME"
    chmod 777 "$MACOSDIR/$APPBASENAME"

    # set app icon
    cp "$APPICON_PATH" "$RESOURCES"
}

# setup express server that app will run on host to handle local api calls
# during install, etc.
setup_server() {
    cp -r "$GUIBUILD"/services/xpeServer/* "$SERVERROOT"
    # make sure npm install done
    cd "$SERVERROOT"
    npm install
}

setup_installer_assets() {
    # functions called by the xpeServer during install
    cp "$XPEINFRAROOT/scripts/local_installer_mac.sh" "$INSTALLER"
    cp "$INSTALLERTARBALL" "$INSTALLER" # the docker images and other files needed by local_installer_mac.sh
}

# arg: URL to curl nwjs build from to include in app
setup_nwjs() {
    setup_nwjs_binary "$1" # the actual nwjs binary, to package in app
    setup_nwjs_root # build root directory for app to point the binary at
}

# arg: URL to curl nwjs build from to include in app
setup_nwjs_binary() {
    # setup nwjs binary
    local nwjs_url="$1"
    local nwjs_zip
    local nwjs_dir
    nwjs_zip=$(basename "$nwjs_url")
    nwjs_dir=$(basename "$nwjs_url" .zip) # name of the unzipped dir

    cd "$BIN"
    curl "$nwjs_url" -O
    unzip -aq "$nwjs_zip"
    rm "$nwjs_zip"
    # must change app metadata to get customized nwjs menus to display app name
    # http://docs.nwjs.io/en/latest/For%20Users/Advanced/Customize%20Menubar/ <- see MacOS section
    find "$nwjs_dir"/nwjs.app/Contents/Resources/*.lproj/InfoPlist.strings -type f -print0 | xargs -0 sed -i 's/CFBundleName\s*=\s*"nwjs"/CFBundleName = "'"$APPBASENAME"'"/g'
    # replace nwjs default icon with app icon (hack for now, not getting icon attr to work)
    # nwjs icon will dispaly on refresh/quit prompts, even when running Xcalar Design app
    cp "$APPICON_PATH" "$nwjs_dir"/nwjs.app/Contents/Resources/app.icns
    cp "$APPICON_PATH" "$nwjs_dir"/nwjs.app/Contents/Resources/document.icns
}

# nwjs binary runs by pointing at a local directory on host; should have a manifest file.
# the manifest file specifies an entrypoint for nwjs.
# our entrypoint is a javascript file, which eventually launches windows with GUIs.
# set up that root directory with the manifest file, the entrypoint, and the
# dependencies for the entrypoint
setup_nwjs_root() {

    # manifest file for nwjs (package.json which instructs what entrypoint is
    # when starting nwjs, browser args, etc.)
    cp "$XPEINFRAROOT/staticfiles/package.json" "$NWJSROOT"
    # nwjs entrypoint specified by the package.json
    cp "$GUIBUILD/assets/js/xpe/starter.js" "$NWJSROOT"

    # copy in the main guis
    cp -r "$GUIBUILD/xpe" "$NWJSROOT/guis"

    # copy in the all the dependencies in the gui repo required for all of these
    # components (the guis, the server, the entrypoint)
    # retain build structure for now
    declare -a dependencies=(
        "3rd/jquery.min.js"
        "3rd/jquery-ui.js"
        "3rd/fonts"
        "assets/fonts"
        "assets/lang/en/globalAutogen.js"
        "assets/js/promiseHelper.js"
        "assets/js/httpStatus.js"
        "assets/js/shared/util/xcHelper.js"
        "assets/stylesheets/css/xpe.css"
        "assets/js/xpe"
        "assets/images/xdlogo.png"
        "assets/images/installer-wave.png"
    )
    for dependency in "${dependencies[@]}"
    do
        # check if it exists if not fail
        if [ ! -e "$GUIBUILD/$dependency" ]; then
            echo "$dependency not found in gui build $GUIBUILD!" >&2
            exit 1
        fi
        # get the top level dir of it
        parentdir="$(dirname "$dependency")"
        mkdir -p "$NWJSROOT/$parentdir"
        cp -r "$GUIBUILD/$dependency" "$NWJSROOT/$dependency"
    done

    # npm install modules required by nwjs' entrypoint which aren't ingui
    # (can't use package.json - it would need to be shared by both
    # nodejs and nwjs; but package.json for nodejs does not allow capital letters
    # in name field, while nwjs' package.json needs name field to match app's name
    #  (Xcalar Design) else it will generate additional Application Support
    # directories by that name.  So require the modules directly]]
    cd "$NWJSROOT/assets"
    npm install jquery
}

setup_bin() {
    setup_nwjs "$NWJS_URL" # nwjs build to curl and include
    # nodejs in to Bin directory
    # make sure you are curling directly in to bin dir
    cd "$BIN" # setup_nwjs will change dir
    curl "$NODE_URL" | tar zxf -
}

# hidden files in the MacOS dir are used on the host at install time, to determine
# how the install should be done.
setup_hidden_files() {
    # file to indicate which img is associated with this installer bundle
    # so host program will know weather to open installer of main app at launch
    # this should have been made by Jenkins job and in cwd
    if ! imgsha=$(docker image inspect "$XCALAR_IMAGE_NAME":lastInstall -f '{{ .Id }}' 2>/dev/null); then
        echo "No $XCALAR_IMAGE_NAME:lastInstall to get image sha from!!" >&2
        exit 1
    else
        echo "$imgsha" > "$DATA/.imgid"
    fi

    # if supposed to build grafana, add a mark for this for host-side install
    if $BUILD_GRAFANA; then
        touch "$MACOSDIR/.grafana"
    fi
    # if a dev build (will expose right click feature in GUIs), add a mark for this for host-side install
    if $DEV_BUILD; then
        touch "$MACOSDIR/.dev"
    fi
}

create_app_structure
setup_required_app_files
setup_server
setup_installer_assets
setup_bin
setup_hidden_files

# echo for other scripts
echo "$APPOUT"
