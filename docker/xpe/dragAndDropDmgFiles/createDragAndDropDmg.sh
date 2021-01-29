#
# This script will create will create a drag and drop dmg for the XPE app.
# It is a wrapper around npm's 'appdmg' tool.
# This script will install, and then delete, app dmg, if it is not installed.
# This must be run on OSX.
# (This script is intended to be run after a XcalarPersonalEditionBuilder
# Jenkins job, via a wrapper script generated during the job which gives
# paramters specific to that job, as a way to create the drag and drop dmg for
# the app the job generates.)
#
# Useage:
#     APPTAR=<tarfile containing app> OUTPATH=<dmg output> bash createDragAndDropDmg.sh
#
# These files must exist in the script dir, at runtime:
#    1. dmgspecifier.json (specifies how appdmg is to be run);
#        can find at: <XLR-INFRA>/docker/xpe/dragAndDropFiles/dmgspecifier.json
#    2. Xcalar_Design_EE_dmg_bg.png (bg image for the dmg, as specified in dmgspecifier.json)
#        can find at <XLR-INFRA>/docker/xpe/dragAndDropFiles/Xcalar_Design_EE_dmg.png
#
# The XcalarPersonalEditionRunner Jenkins should create a dir in each build,
# which includes this script, as well as those dependencies.
#
# Note:: the file 'dmgspecifier.json', is what the appdmg tool uses to determine
# where is the app it will create a dmg for, where is the bg image for the dmg,
# etc.  Right now, the json file is hardcoded.  So you can not just supply any
# app to this script; the app in the tarfile you supply, must be the name of the
# app specified in the dmgspecifier.json for this to work.
#
# (Need the app within a tarfile because the nwjs binaries are not world readable,
# and won't be able to copy the app itself from netstore on to remote Mac without sudo,
# and the major use case is the app being located on a Jenkins build dir on netstore
# for the 'XcalarPersonalEditionRunner' job, with user running this from a mac
# post-build.)

set -e

: "${OUTPATH:?Need to set non-empty OUTPATH (path to output .dmg)}"
: "${APPTAR:?Need to supply non-empty APPTAR (path to tarfile containing the .app)}"

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
START_CWD=$(pwd)
CONFIGDIR="${CONFIGDIR:-"$SCRIPTDIR"}" # where dependent files are

# make sure tarfile exists
if [ ! -e "$APPTAR" ]; then
    echo "Can't find APPTAR $APPTAR" >&2
    exit 1
fi
# make sure OUTPATH is .dmg
if [[ ! "$OUTPATH" == *.dmg ]]; then
    echo "OUTPATH must end in .dmg" >&2
    exit 1
fi
# if outpath already exists fail unless force
if [[ -e "$OUTPATH" ]]; then
    echo "OUTPATH $OUTPATH already exists" >&2
    exit 1
fi
# make sure script being run from a Mac
if [[ $OSTYPE != *"darwin"* ]]; then
    echo "This script must be run from a Mac!" >&2
    exit 1
fi
# make sure node/npm installed
if ! type -P npm > /dev/null; then
    echo "You must have node/npm installed to run this script." >&2
    exit 1
fi

echo "
Creating drag and drop dmg... this will take approx 5 minutes, please wait..." >&2

# create a tmp dir to install and run appdmg in
STAGING_DIR="$(mktemp -d /tmp/mkDragNDropXXXXXX)"
trap "rm -r $STAGING_DIR" EXIT SIGTERM SIGINT

# untar the app
# do this within cwd of script start in case rel path was supplied for the app
tar zxf "$APPTAR" -C "$STAGING_DIR"
# make sure app inside and get name
if ! cd "$STAGING_DIR"/*.app; then
    echo "Could not find .app in tarfile" >&2
    exit 1
else
    APPPATH=$(pwd)
fi
cd "$STAGING_DIR"
# todo: make sure app path is one specified in dmgspecifier.json, in case that file
# ever changes and build process needs to be updated. alternatively, could
# autogen the dmgspecifier.json file, based on app user supplied.
# (json file shows appdmg tool where to look for the app, right now its hardcoded)

# files/dirs required to be in same dir appdmg is run from
# note: dmgspecifier.json is actually what specifies where the other files are,
# if things ever stop working/files not exist, check that json file.
CONFIGFILE="dmgspecifier.json"
REQ_FILES=("$CONFIGDIR/$CONFIGFILE" "$CONFIGDIR/XPE_dmg_bg.png")

# copy in files required to run appdmg
echo "Copying required files to staging dir..." >&2
for i in "${REQ_FILES[@]}"
do
    cp -R "$i" "$STAGING_DIR"
done

# install appdmg in staging dir
echo "Installing appdmg locally in staging dir $STAGING_DIR (npm)" >&2
cd "$STAGING_DIR"
npm install appdmg

# run appdmg - dmg will be at output path (2nd arg)
# $CONFIGFILE - this is a json that specifies the dmg config
# it specifies where is the app, bg img, etc.
DMG_BASENAME=$(basename "$OUTPATH")
set -x
node_modules/.bin/appdmg "$CONFIGFILE" "$STAGING_DIR/$DMG_BASENAME"
set +x

# copy dmg to requested output location
# (if OUTPATH was just a dmg file, output in cwd when script began)
DMG_DIRNAME="$(dirname "$OUTPATH")"
if  [[ "$DMG_DIRNAME" == "." ]]; then
    DMG_DIRNAME="$START_CWD"
fi
mkdir -p "$DMG_DIRNAME"

# could take some time; don't get them confused by the appdmg output
echo "
Copying image to final location; please wait... " >&2
cp "$STAGING_DIR"/"$DMG_BASENAME" "$DMG_DIRNAME"

# check for BLDINFO.txt in dir containing the app the dmg was made from;
# if there copy also to final location
# (if the dir was a Jenkins build dir it should be there, contains useful
# info about the build such as which installer was used, etc which could be useful for dmg)
buildDir="$(dirname "$APPTAR")"
if [ -e "$buildDir/BLDINFO.txt" ]; then
    cp "$buildDir/BLDINFO.txt" "$DMG_DIRNAME"
fi

# print a helpful summary to stderr
dmgFullPath="$DMG_DIRNAME/$DMG_BASENAME"
dmgFullPathWsBackTickSub=${dmgFullPath// /\\ } # backtick ws in path
finalMsg="

========================

Dmg located at:

    $dmgFullPathWsBackTickSub

=======================
"
# if OUTPATH is on netstore  give a helpful curl cmd that can be distributed
# substitute all whitespace in the path with '%20' for the curl cmd.
# (auto-genned bash script created by XcalarDesignPersonalEditionBuilder job which
# runs this script, will put the outpath on netstore)
if [[ $dmgFullPath = *"netstore"* ]]; then
    dmgFullPathWsSub=${dmgFullPath// /%20}
    dmgFileNameWsSub=${DMG_BASENAME// /\\ }

    finalMsg="$finalMsg
Curl to get dmg::

    curl http:/$dmgFullPathWsSub -o "$dmgFileNameWsSub"

========================

"
fi

echo "$finalMsg" >&2
