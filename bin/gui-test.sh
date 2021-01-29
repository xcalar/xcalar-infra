#!/bin/bash
#
# Given a hostname (such as preview-foo-1.xcalar.cloud) this
# script prints out the URL to open to start the UI regression tests
# On OSX, if --open is passed, the script will open Chrome to the
# test url

test -z "$1" && {
    echo >&2 "Need to specify hostname/IP"
    exit 1
}

URL="http://${1}/test.html?auto=y&server=localhost%3A5909&users=5&mode=ten&host=${1}&close=force"
echo "$URL"

# On OSX, open the test url in Chrome, if --open was passed
if [ "$2" = "--open" ] && [ -n "$DISPLAY" ] && [ "$(uname -s)" = Darwin ]; then
    cat <<EOF | osascript -
tell application "Google Chrome"
    activate
    open location "$URL"
    delay 1
    activate
end tell
EOF
fi
