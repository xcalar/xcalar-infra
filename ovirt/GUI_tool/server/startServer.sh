##
## run this file to start up the Flask server for vmshop in a new virtual env.
## it will start an http server
##
## To use https::
## * start Caddy in <infra>/ovirt/GUI_tool/frontend using custom Caddyfile
##   at <infra>/ovirt/serveri/vmshop_caddyfile.conf;
##  it will proxy https::<>/flask requests to this http server
##  (ex to start caddy):
##    cd $XLRINFRADIR/ovirt/GUI_tool/frontend && caddy -conf=$XLRINFRADIR/ovirt/GUI_tool/server/vmshop_caddyfile.conf

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

trap cleanup EXIT SIGTERM SIGINT # Jenkins sends SIGTERM on abort

###
### set up a new virtual env
###

deactivate 2>/dev/null || true
VIRTUAL_ENV="$SCRIPT_DIR/.venv"
if [ ! -d "$VIRTUAL_ENV" ]; then
    virtualenv -p /opt/xcalar/bin/python3 "$VIRTUAL_ENV"
fi
source "$VIRTUAL_ENV"/bin/activate

###
### download 3rd party code used by the GUI from repo.xcalar.net/deps
###

# create 3rd dir if not there (clean dir)
THIRD_PARTY_CODE="$SCRIPT_DIR/../frontend/assets/3rd"
if [ ! -d "$THIRD_PARTY_CODE" ]; then
    echo "doesnt exist"
    mkdir -p "$THIRD_PARTY_CODE"
fi

# materialize (don't overwrite if exists in case made local mods)
MATERIALIZE="materialize-v1.0.0.zip"
LOC_MAT_ZIP="$THIRD_PARTY_CODE/$MATERIALIZE"
# inside is just a dir called 'materialize'
LOC_MAT_UNZIPPED=$(dirname "${LOC_MAT_ZIP}")/materialize
if [ ! -d "$LOC_MAT_UNZIPPED" ]; then
    curl http://repo.xcalar.net/deps/$MATERIALIZE -o "$LOC_MAT_ZIP"
    unzip -d $(dirname "$LOC_MAT_ZIP") "$LOC_MAT_ZIP"
    rm "$LOC_MAT_ZIP" # just get rid the zip file
fi

# jquery
if [ ! -f "$THIRD_PARTY_CODE/jquery.ui.js" ]; then
    curl http://repo.xcalar.net/deps/ovirt/guitool/jquery-ui.js -o "$THIRD_PARTY_CODE/jquery-ui.js"
fi
if [ ! -f "$THIRD_PARTY_CODE/jquery.min.js" ]; then
    curl http://repo.xcalar.net/deps/ovirt/guitool/jquery.min.js -o "$THIRD_PARTY_CODE/jquery.min.js"
fi

##
## append <infra>/bin to path; Flask server uses ovirt/modules/OvirtUtils.py
## for validating URL. ovirt/modules/OvirtUtils.py calls a bash script directly
## to do that, and that bash script is <infra>/bin and needs to be in path
##
BINDIR="$SCRIPT_DIR/../../../bin"
APPENDPATH="$BINDIR:${PATH}"
export PATH="$APPENDPATH"

###
### install python deps for the server!
###
pip install -r "$SCRIPT_DIR/requirements.txt"

cd "$SCRIPT_DIR" && FLASK_APP=FlaskServerOvirt.py flask run --host=0.0.0.0
