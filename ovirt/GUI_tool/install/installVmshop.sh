# Run this bash script to set up the servers required for
# the ovirttool GUI on a Centos7 machine.
# This script will set up systemd services for the flask (http)
# and Caddy (https) servers for the GUI, and enables them to run
# on machine reboot.
# If the services are already setup the script will do nothing.
#
# usage:
#   bash setupVmshop.sh <USER>
#   where <USER> is user you want the systemd services running as

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SYSTEMD_TEMPLATE_FILES_DIR="$SCRIPT_DIR/systemd_service_templates"
SYSTEMD_SERVICES_DIR="/etc/systemd/system" # where the systemd service files will go
FLASK_SYSTEMD_SERVICE_NAME="vmshopflask"
FLASK_SERVICE_TEMPLATE_FILE="$SYSTEMD_TEMPLATE_FILES_DIR/vmshopflask.service.template"
FLASK_SYSTEMD_FILE="$SYSTEMD_SERVICES_DIR/$FLASK_SYSTEMD_SERVICE_NAME".service
CADDY_SYSTEMD_SERVICE_NAME="vmshopcaddy"
CADDY_SERVICE_TEMPLATE_FILE="$SYSTEMD_TEMPLATE_FILES_DIR/vmshopcaddy.service.template"
CADDY_SYSTEMD_FILE="$SYSTEMD_SERVICES_DIR/$CADDY_SYSTEMD_SERVICE_NAME".service
SYSTEMD_USER="" # gets set as first arg; will run systemd services as this user
# placeholder text being used in the template files that we'll sed with args passed to this script
USER_PLACEHOLDER="@USER@"
INFRADIR_PLACEHOLDER="@XLRINFRADIR@"

# make sure they have passed first arg
if [ -z "$1" ]; then
    echo "Must pass first arg; user to setup systemd services as" >&2
    exit 1
else
    SYSTEMD_USER="$1"
fi

if [ -z "$XLRINFRADIR" ]; then
    echo "You must have xcalar-infra repo to run this install!" >&2
    exit 1
fi

cat << EOF

***
This script will now set up and enable systemd services to run the ovirttool GUI on this machine.

WARNING: If you are running this on a new VM:

(1) if the VM's hostname is NOT 'vmshop', make sure to modify the file:
$XLRINFRADIR/ovirt/GUI_tool/assets/js/ovirtGuiScripts.js
and specify the correct SERVER_URL to https://<vm's hostname>:1224, so API requests
will be directed to the Flask server that will be set up on this machine.

(2) Copy .crt and .key files to $XLRINFRADIR/ovirt/GUI_tool/server and update
the tls directive in the Caddyfile for the caddy server which will be set up on this machine:
$XLRINFRADIR/ovirt/GUI_tool/service/vmshop_caddyfile.confg
-- you will then need to restart the caddy service
 sudo systemctl stop <caddy service>
 sudo systemctl start <caddy service>
***
EOF

# starts a given systemd services and enables for auto-start on boot
function kickstart_service() {
    if [ -z "$1" ]; then
        echo "must pass service name to start as first positional arg to kickstart_service" >&2
        exit 1
    else
       sudo systemctl enable "$1"
       sudo systemctl start "$1"
       echo "systemd '$1' service started... run 'sudo systemctl stop $1' to stop service." >&2
    fi
}

# takes a template for a systemd config file, and output location and creates the systemd file
# then starts the systemd service
# 1st arg: path to template file
# 2nd arg: path to systemd service file that should be created
# relies on args passed to larger script for generating systemd file from template
function setup_systemd_service() {
    local template_file=""
    local serviced_file_out=""
    if [ -z "$1" ]; then
        echo "must specify template file as first positional arg to setup_systemd_service!" >&2
        exit 1
    else
        template_file="$1"
    fi
    if [ -z "$2" ]; then
        echo "must specify output for systemd config file as second positional arg to setup_systemd_service!" >&2
        exit 1
    else
        serviced_file_out="$2"
    fi
    local service_name
    service_name="$(basename "$serviced_file_out" .service)"
    echo "" >&2
    echo "Setting up systemd file $serviced_file_out for service '$service_name' ..." >&2
    sudo cp "$template_file" "$serviced_file_out"
    sudo sed -i 's/'"$USER_PLACEHOLDER"/"$SYSTEMD_USER"'/g' "$serviced_file_out"
    sudo sed -i 's+'"$INFRADIR_PLACEHOLDER"+"$XLRINFRADIR"'+g' "$serviced_file_out" # using a different sed delimiter because '/' likely in replacement val
    kickstart_service "$service_name"
}

# set up service for Caddy server
if [ ! -f "$CADDY_SYSTEMD_FILE" ]; then
    setup_systemd_service "$CADDY_SERVICE_TEMPLATE_FILE" "$CADDY_SYSTEMD_FILE"
fi

# set up service for Flask server
if [ ! -f "$FLASK_SYSTEMD_FILE" ]; then
    setup_systemd_service "$FLASK_SERVICE_TEMPLATE_FILE" "$FLASK_SYSTEMD_FILE"
fi

cat << EOF

To re-enable after modifications to any of the above service files, run:
 sudo systemctl daemon-reload
 sudo systemctl reenable <service name>

EOF

