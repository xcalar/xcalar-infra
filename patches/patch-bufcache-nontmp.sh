#!/bin/bash

XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
XCE_TEMPLATE=${XCE_TEMPLATE:-$(dirname $XCE_CONFIG)/template.cfg}

xcalar_version() {
    if [ -n "$XCALAR_VERSION" ]; then
        echo $XCALAR_VERSION
        return 0
    fi
    rpm -q xcalar --qf '%{VERSION}' | sed 's/\./ /g'
}

temp_fix_swapsettings() {
    local -a version
    if ! version=($(xcalar_version)); then
        return 1
    fi
    # 2.0.4, but not 2.2.x
    if [ ${version[0]} -eq 2 ] && [ ${version[1]} -lt 2 ] && [ ${version[2]} -ge 4 ]; then
        XCE_BACKUP="${XCE_TEMPLATE%.*}".bak
        cp -n ${XCE_TEMPLATE} ${XCE_BACKUP}
        (
        head -3 ${XCE_BACKUP}
        echo
        echo 'Constants.BufCacheNonTmpFs=true'
        echo 'Constants.XdbSerDesMode=2'
        echo 'Constants.XdbLocalSerDesPath=/ephemeral/data/serdes/'
        echo 'Constants.XdbSerDesMaxDiskMB=0'
        echo 'Constants.BufferCachePath=/ephemeral/data/serdes'
        echo 'Constants.EnforceVALimit=false'
        echo
        tail -n +4 ${XCE_BACKUP}
        ) > ${XCE_TEMPLATE}
    fi
    return 0
}

temp_fix_swapsettings "$@"
