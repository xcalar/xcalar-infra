#!/bin/bash
export XLRINFRADIR="${XLRINFRADIR:-$XLRDIR/xcalar-infra}"
export XLRGUIDIR="${XLRGUIDIR:-$XLRDIR/xcalar-gui}"
export XCE_LICENSEDIR=$XLRDIR/src/data
export XCE_LICENSEFILE=${XCE_LICENSEDIR}/XcalarLic.key

. $XLRDIR/bin/jenkins/jenkinsUtils.sh

NUM_USERS=${NUM_USERS:-$(shuf -i 2-3 -n 1)}
TEST_DRIVER_PORT="5909"
NETSTORE="/netstore/qa/jenkins"

collectFaildLogs() {
    mkdir -p /var/log/xcalar/failedLogs || true
    if [ "$useXc2" == "true" ]; then
        cp -r "/tmp/xce-`id -u`"/* /var/log/xcalar/failedLogs/
    else
        cp $XLRDIR/$TmpSqlDfLogs /var/log/xcalar/failedLogs/
    fi
    cp $TmpCaddyLogs /var/log/xcalar/failedLogs/

    if [ -x "${XLRDIR}/bin/caddy.sh" ]; then
        CADDYHOME="$TmpCaddyDir" "$XLRDIR"/bin/caddy.sh stop
    else
        pkill -F $TmpCaddyPid || true
    fi
}

onExit() {
    local retval=$?
    set +e

    if [[ $retval != 0 ]]
    then
        collectFaildLogs
        genBuildArtifacts
        echo "Build artifacts copied to ${NETSTORE}/${JOB_NAME}/${BUILD_ID}"
    fi

    (xclean; kill $(jobs -p) || true)
    exit $retval
}

trap onExit SIGINT SIGTERM EXIT

storeExpServerCodeCoverage() {
    outputDir=/netstore/qa/coverage/${JOB_NAME}/${BUILD_ID}
    mkdir -p "$outputDir"
    covReportDir=$XLRGUIDIR/xcalar-gui/services/expServer/test/report

    if [ -d "$covReportDir" ]; then
        echo "expServer code coverage report copied to ${outputDir}"
        cp -r "$covReportDir"/* "${outputDir}"
    else
        echo "code coverage report folder doesn't exist on ${covReportDir}"
    fi
}

storeXDUnitTestCodeCoverage() {
    covReport=$XLRGUIDIR/assets/dev/unitTest/coverage/coverage.json
    if [ -f "$covReport" ]; then
        outputDir=/netstore/qa/coverage/${JOB_NAME}/${BUILD_ID}
        mkdir -p "$outputDir"
        echo "XDUnitTest coverage report copied to ${outputDir}"
        cp -r "${covReport}" "${outputDir}"
        gzip "$outputDir/coverage.json"
        # Record the branch configurations
        echo "XCE_GIT_BRANCH: $XCE_GIT_BRANCH" > "$outputDir/git_branches.txt"
        echo "XD_GIT_BRANCH: $XD_GIT_BRANCH" >> "$outputDir/git_branches.txt"
        echo "INFRA_GIT_BRANCH: $INFRA_GIT_BRANCH" >> "$outputDir/git_branches.txt"
    else
        echo "code coverage report doesn't exist at ${covReport}"
    fi
}

runExpServerIntegrationTest() {
    set +e
    xc2 cluster stop # Stop the one node cluster that was started for GerritExpServerTest, to let pytest start a cluster on its own.
    currentDir=$PWD
    local retval=0

    cd $XLRDIR/src/bin/tests/pyTestNew
    testCases=("test_dataflow_service.py" "test_workbooks_new" "test_dfworkbooks_execute.py" "test_dataflows_execute.py")

    echo "running integration test for expServer"
    for testCase in "${testCases[@]}"; do
        echo "running test $testCase"
        ./PyTest.sh -k "$testCase"
        local ret=$?
        if [ $ret -ne "0" ]; then
            retval=1
            break
        fi
    done

    cd $currentDir
    set -e
    return $retval
}

checkApiVersionSig() {
    local VERSION_SIG="$1"
    local VERSION_FILE="$2"

    local ret=1
    if [ -f "$VERSION_FILE" ] && [ -n "$VERSION_SIG" ]; then
        if grep -q "$VERSION_SIG" $VERSION_FILE; then
            ret=0
        fi
    fi
    return $ret
}
generateXcrpcVersionSig() {
    local PROTO_DIR="$1"

    local checkFiles=$(find $PROTO_DIR -name "*.proto" | LC_ALL=C sort)
    local totalValue=""
    local newline=$'\n'
    local protoFile
    for protoFile in $checkFiles; do
        local checkSum=$(md5sum $protoFile | cut -d " " -f 1)
        totalValue="$totalValue$checkSum${newline}"
    done
    echo -n "$totalValue" | md5sum | cut -d " " -f 1
}
generateThriftVersionSig() {
    local DEF_FILE="$1"
    md5sum $DEF_FILE | cut -d " "  -f 1
}
generateThriftVersionSigNew() {
    local newline=$'\n'
    local files=""
    for defFile in "$@"; do
        if [ -f "$defFile" ]; then
            files="${files} ${defFile}"
        fi
    done

    local content="$(cat ${files})${newline}"
    echo -n "$content" | md5sum | cut -d " " -f 1
}

if [ $JOB_NAME = "GerritSQLCompilerTest" ]; then
    cd $XLRGUIDIR
    git diff --name-only HEAD^1 > out
    echo `cat out`
    diffTargetFile=`cat out | grep -E "(assets\/test\/json\/SQLTest-a.json|assets\/extensions\/ext-available\/sql.ext|ts\/components\/sql\/|ts\/thrift\/XcalarApi.js|ts\/shared\/api\/xiApi.ts|ts\/components\/worksheet\/oppanel\/SQL.*|ts\/XcalarThrift.js|ts\/components\/dag\/node\/.*SQL.*|ts\/components\/dag\/(DagView.ts|DagGraph.ts|DagSubGraph.ts|DagTab.ts|DagTabManager.ts|DagTabSQL.ts))" | grep -v "ts\/components\/sql\/sqlQueryHistoryPanel.ts"`

    rm -rf out

    if [ -n "$diffTargetFile" ] || [ "$RUN_ANYWAY" = "true" ]
    then
        echo "Change detected"
    else
        echo "No target file changed"
        exit 0
    fi
fi

install_reqs() {
    echo "Installing required packages"
    if grep -q Ubuntu /etc/os-release; then
        sudo apt-get install -y libnss3-dev chromium-browser
        sudo apt-get install -y libxss1 libappindicator1 libindicator7 libgconf-2-4
        sudo apt-get install -y Xvfb
        if [ ! -f /usr/bin/chromedriver ]; then
            echo "Wget chrome driver"
            wget http://chromedriver.storage.googleapis.com/2.24/chromedriver_linux64.zip
            unzip chromedriver_linux64.zip
            chmod +x chromedriver
            sudo mv chromedriver /usr/bin/
        else
            pwd
            echo "Chrome driver already installed"
        fi
    else
        sudo curl -ssL http://repo.xcalar.net/rpm-deps/google-chrome.repo | sudo tee /etc/yum.repos.d/google-chrome.repo
        curl -sSO https://dl.google.com/linux/linux_signing_key.pub
        sudo rpm --import linux_signing_key.pub
        rm linux_signing_key.pub
        sudo yum install -y google-chrome-stable
        sudo yum localinstall -y /netstore/infra/packages/chromedriver-2.34-2.el7.x86_64.rpm
        sudo yum install -y Xvfb
    fi
}

pip install pyvirtualdisplay selenium

if [ "$AUTO_DETECT_XCE" = "true" ]; then
    xcrpcDefDir="$XLRDIR/src/include/pb/xcalar/compute/localtypes"
    xcrpcVersionFile="$XLRGUIDIR/assets/js/xcrpc/enumMap/XcRpcApiVersion/XcRpcApiVersionToStr.json"
    thriftDefFileH="$XLRDIR/src/include/libapis/LibApisCommon.h"
    thriftDefFile="$XLRDIR/src/include/libapis/LibApisCommon.thrift"
    PKG_LANG="en"
    # This is for thrift version on trunk
    thriftDefFileList=(
        "$XLRDIR/src/include/libapis/LibApisCommon.thrift"
        "$XLRDIR/src/include/libapis/LibApisCommon.h"
        "$XLRDIR/src/include/UdfTypeEnums.enum"
        "$XLRDIR/src/include/SourceTypeEnum.enum"
        "$XLRDIR/src/include/OrderingEnums.enum"
        "$XLRDIR/src/include/DataFormatEnums.enum"
        "$XLRDIR/src/include/JsonGenEnums.enum"
        "$XLRDIR/src/include/JoinOpEnums.enum"
        "$XLRDIR/src/include/UnionOpEnums.enum"
        "$XLRDIR/src/include/XcalarEvalEnums.enum"
        "$XLRDIR/src/include/DagStateEnums.enum"
        "$XLRDIR/src/include/DagRefTypeEnums.enum"
        "$XLRDIR/src/include/QueryParserEnums.enum"
        "$XLRDIR/src/include/libapis/LibApisEnums.enum"
        "$XLRDIR/src/include/libapis/LibApisConstants.enum"
        "$XLRDIR/src/include/QueryStateEnums.enum"
        "$XLRDIR/src/include/DataTargetEnums.enum"
        "$XLRDIR/src/include/CsvLoadArgsEnums.enum"
        "$XLRDIR/src/include/license/LicenseTypes.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/Subsys.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/StatusCode.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/FunctionCategory.enum"
        "$XLRDIR/src/include/runtime/RuntimeEnums.enum"
    )
    # This is for thrift version on 2.0 branch
    # It involves the same files as trunk but with slightly different order
    thriftDefFileList2=(
        "$XLRDIR/src/include/libapis/LibApisCommon.h"
        "$XLRDIR/src/include/libapis/LibApisCommon.thrift"
        "$XLRDIR/src/include/UdfTypeEnums.enum"
        "$XLRDIR/src/include/SourceTypeEnum.enum"
        "$XLRDIR/src/include/OrderingEnums.enum"
        "$XLRDIR/src/include/DataFormatEnums.enum"
        "$XLRDIR/src/include/JsonGenEnums.enum"
        "$XLRDIR/src/include/JoinOpEnums.enum"
        "$XLRDIR/src/include/UnionOpEnums.enum"
        "$XLRDIR/src/include/XcalarEvalEnums.enum"
        "$XLRDIR/src/include/DagStateEnums.enum"
        "$XLRDIR/src/include/DagRefTypeEnums.enum"
        "$XLRDIR/src/include/QueryParserEnums.enum"
        "$XLRDIR/src/include/libapis/LibApisEnums.enum"
        "$XLRDIR/src/include/libapis/LibApisConstants.enum"
        "$XLRDIR/src/include/QueryStateEnums.enum"
        "$XLRDIR/src/include/DataTargetEnums.enum"
        "$XLRDIR/src/include/CsvLoadArgsEnums.enum"
        "$XLRDIR/src/include/license/LicenseTypes.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/Subsys.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/StatusCode.enum"
        "$XLRDIR/src/data/lang/${PKG_LANG}/FunctionCategory.enum"
        "$XLRDIR/src/include/runtime/RuntimeEnums.enum"
        "$XLRDIR/src/include/LogLevel.enum"
        "$XLRDIR/src/include/querymanager/DataflowEnums.enum"
    )
    thriftVersionFile="$XLRGUIDIR/ts/thrift/XcalarApiVersionSignature_types.js"

    echo "Detecting version of XCE to use"
    cd $XLRDIR
    foundVersion="false"
    isCheckXcrpc="true"
    checkOutFiles="${thriftDefFileList2[@]} $thriftDefFile $thriftDefFileH $xcrpcDefDir"
    if [ ! -f "$xcrpcVersionFile" ]; then
        isCheckXcrpc="false"
        checkOutFiles="${thriftDefFileList2[@]} $thriftDefFile $thriftDefFileH"
        echo "Skip xcrpc check"
    fi
    versionSigThriftNew=$(generateThriftVersionSigNew "${thriftDefFileList[@]}")
    versionSigThriftNew2=$(generateThriftVersionSigNew "${thriftDefFileList2[@]}")
    versionSigThrift=$(generateThriftVersionSig $thriftDefFile)
    versionSigThriftH=$(generateThriftVersionSig $thriftDefFileH)
    checkApiVersionSig $versionSigThriftNew $thriftVersionFile || checkApiVersionSig $versionSigThriftNew2 $thriftVersionFile || checkApiVersionSig $versionSigThrift $thriftVersionFile || checkApiVersionSig $versionSigThriftH $thriftVersionFile
    foundVerThrift=$?
    if [ $isCheckXcrpc == "true" ]; then
        versionSigXcrpc=$(generateXcrpcVersionSig $xcrpcDefDir)
        checkApiVersionSig $versionSigXcrpc $xcrpcVersionFile
        foundVerXcrpc=$?
    else
        versionSigXcrpc="N/A"
        foundVerXcrpc=0
    fi
    if [ $foundVerThrift -eq 0 ] && [ $foundVerXcrpc -eq 0 ]; then
        echo "Current version of XCE is compatible"
        foundVersion="true"
    else
        echo "Current: ThriftVersionSigNew2 = $versionSigThriftNew2; ThriftVersionSig = $versionSigThrift; XcrpcVersionSig = $versionSigXcrpc"
        echo "Current version of XCE is not compatible. Trying..."
        gitshas=`git log --format=%H -- $checkOutFiles`
        prevSha="HEAD"
        for gitsha in $gitshas; do
            if ! git checkout "$gitsha"; then
                break
            fi
            versionSigThriftNew=$(generateThriftVersionSigNew "${thriftDefFileList[@]}")
            versionSigThriftNew2=$(generateThriftVersionSigNew "${thriftDefFileList2[@]}")
            versionSigThrift=$(generateThriftVersionSig $thriftDefFile)
            versionSigThriftH=$(generateThriftVersionSig $thriftDefFileH)
            checkApiVersionSig $versionSigThriftNew $thriftVersionFile || checkApiVersionSig $versionSigThriftNew2 $thriftVersionFile || checkApiVersionSig $versionSigThrift $thriftVersionFile || checkApiVersionSig $versionSigThriftH $thriftVersionFile
            foundVerThrift=$?
            if [ $isCheckXcrpc == "true" ]; then
                versionSigXcrpc=$(generateXcrpcVersionSig $xcrpcDefDir)
                checkApiVersionSig $versionSigXcrpc $xcrpcVersionFile
                foundVerXcrpc=$?
            else
                versionSigXcrpc="N/A"
                foundVerXcrpc=0
            fi
            echo "$gitsha: ThriftVersionSigNew2 = $versionSigThriftNew2; ThriftVersionSig = $versionSigThrift; XcrpcVersionSig = $versionSigXcrpc"
            if [ $foundVerThrift -eq 0 ] && [ $foundVerXcrpc -eq 0 ]; then
                echo "$gitsha is a match"
                echo "Checking out $prevSha as the last commit with the matching signature"
                #git checkout HEAD $checkOutFiles
                git checkout "$prevSha"
                git submodule update --init --recursive xcalar-idl
                foundVersion="true"
                break
            else
                prevSha="$gitsha^1"
            fi
        done
    fi

    if [ "$foundVersion" = "false" ]; then
        echo "Could not find a compatible version of XCE to use"
        exit 1
    fi
fi

echo "Building XCE"
cd $XLRDIR
set +e
source doc/env/xc_aliases
xclean
set -e
cmBuild clean
cmBuild config prod
if [ $JOB_NAME = "GerritExpServerTest" ]; then
    cmBuild xce
    cmBuild qa
else
    cmBuild xce
fi

echo "Building XD"
cd $XLRGUIDIR

if [ $JOB_NAME = "XDFuncTest" ]; then
    make dev PRODUCT="$GUI_PRODUCT"
else
    make debug PRODUCT="$GUI_PRODUCT"
fi

if [ "$GUI_PRODUCT" = "XI" ]; then
    GUI_FOLDER=xcalar-insight
    echo "Using xcalar-insight"
else
    GUI_FOLDER=xcalar-gui
    echo "Using xcalar-gui"
fi

cd $XLRDIR

mkdir -p src/sqldf/sbt/target
if  [ -f "${XLRDIR}/bin/download-sqldf.sh" ] && \
    [ -f  "${XLRDIR}/src/3rd/spark/BUILD_ENV" ]; then
    SQLDF_VERSION="$(. ${XLRDIR}/src/3rd/spark/BUILD_ENV; echo $SQLDF_VERSION)"
    export SQLDF_VERSION
    ${XLRDIR}/bin/download-sqldf.sh $XLRDIR/src/sqldf/sbt/target/xcalar-sqldf.jar
else
    tar --wildcards -xOf /netstore/builds/byJob/BuildSqldf-with-spark-branch/lastSuccessful/archive.tar xcalar-sqldf-*.noarch.rpm | rpm2cpio | cpio --to-stdout -i ./opt/xcalar/lib/xcalar-sqldf.jar >$XLRDIR/src/sqldf/sbt/target/xcalar-sqldf.jar
fi

export NODE_ENV=dev
if [ "`xc2 --version`" == "xc2, version 1.4.1" ]; then
    useXc2="false"
    TmpSqlDfLogs=`mktemp SqlDf.XXXXX.log`
    echo "Starting SQLDF"
    # loader.sh expects an existing defaultAdmin.json file to have 600
    # permissions. fix that if the file exists.
    if [ -f "/var/opt/xcalar/config/defaultAdmin.json" ]; then
        chmod 0600 /var/opt/xcalar/config/defaultAdmin.json
    fi

    java -jar $XLRDIR/src/sqldf/sbt/target/xcalar-sqldf.jar >"$TmpSqlDfLogs" 2>&1 &

    echo "Starting usrnodes"
    export XCE_CONFIG="${XCE_CONFIG:-$XLRDIR/src/bin/usrnode/test-config.cfg}"
    launcher.sh 1 daemon
else
    useXc2="true"
    export XCE_CONFIG="${XCE_CONFIG:-$XLRDIR/src/data/test.cfg}"
    xc2 cluster start --num-nodes 1
fi


echo "Starting Caddy"
pkill caddy || true
TmpCaddyDir=`mktemp -d -t Caddy.XXXXXX`
TmpCaddy=$TmpCaddyDir/Caddyfile
cp $XLRDIR/conf/Caddyfile "$TmpCaddy"
sed -i -e 's!/var/www/xcalar-gui!'$XLRGUIDIR'/'$GUI_FOLDER'!g' "$TmpCaddy"
# strip out the jwt settings for testing (for now) to allow unauthenticated access
sed -i -e '/jwt {/,/}/d' "$TmpCaddy"
sed -i 's@{\$XCE_LOGDIR}@'${TmpCaddyDir}'@' "$TmpCaddy"
sed -i 's/log .*$/log stdout/; s/errors .*$/errors stderr/' "$TmpCaddy"

if [ -x "${XLRDIR}/bin/caddy.sh" ]; then
    CADDYHOME="$TmpCaddyDir" "$XLRDIR"/bin/caddy.sh start -c "$TmpCaddy" -p 8443
    TmpCaddyLogs="$TmpCaddyDir/caddy*.log"
else
    TmpCaddyLogs=$TmpCaddyDir/CaddyLogs.log
    TmpCaddyPid=$TmpCaddyDir/caddy.pid
    echo "Caddy logs at $TmpCaddyLogs"
    cd $TmpCaddyDir
    caddy -pidfile $TmpCaddyPid -https-port 8443 >"$TmpCaddyLogs" 2>&1 </dev/null &
    cd - >/dev/null
    caddyPid=$!
    echo "Caddy pid $caddyPid running in $TmpCaddyDir. Pidfile=$TmpCaddyPid ($(cat $TmpCaddyPid))"
fi
sleep 5

if [ $JOB_NAME = "XDEndToEndTest" ]; then
    cd $XLRGUIDIR/assets/dev/e2eTest
    npm install
else
    cd $XLRGUIDIR/assets/dev/unitTest
    # Please don't ask me why I have to independently install this package.
    # This is the only way I've found to make it work.
    npm install node-bin-setup
    npm install
fi

curl -s http://localhost:27000/xcesql/info |jq '.'
exitCode=1
echo "Starting test driver"
if  [ $JOB_NAME = "GerritSQLCompilerTest" ]; then
    npm test -- sqlTest https://localhost:8443
    exitCode=$?
elif [ $JOB_NAME = "XDUnitTest" ]; then
    npm test -- unitTest https://localhost:8443
    exitCode=$?
    if [ "$STORE_COVERAGE" = "true" ]; then
        storeXDUnitTestCodeCoverage
    fi
elif [ $JOB_NAME = "GerritExpServerTest" ]; then
    npm test -- expServer https://localhost:8443
    exitCode=$?
    if [ "$STORE_COVERAGE" = "true" ]; then
        storeExpServerCodeCoverage
    fi
    if [ $exitCode = "0" ]; then
        runExpServerIntegrationTest
        exitCode=$?
    fi
elif [ $JOB_NAME = "GerritXcrpcIntegrationTest" ]; then
    npm test -- xcrpcTest https://localhost:8443
    exitCode=$?
elif [ $JOB_NAME = "XDTestSuite" ]; then
    npm test -- testSuite https://localhost:8443
    exitCode=$?
elif [ $JOB_NAME = "XDEndToEndTest" ]; then
    sudo yum install -y google-chrome-stable
    google-chrome --version
    chromedriver --version
    npm test -- --tag "allTests" --env jenkins
    exitCode=$?
elif [ $JOB_NAME = "XDFuncTest" ]; then
    npm test -- XDFuncTest https://localhost:8443 $NUM_USERS $ITERATIONS
    exitCode=$?
fi


if [ -x "${XLRDIR}/bin/caddy.sh" ]; then
    CADDYHOME="$TmpCaddyDir" "$XLRDIR"/bin/caddy.sh stop
else
    pkill -F $TmpCaddyPid || true
    kill -TERM $caddyPid || true
fi
sudo unlink /var/www/xcalar-gui || true

if [ "$useXc2" == "true" ]; then
    xc2 cluster stop
fi
if [ $exitCode -eq 0 ]; then
    rm -rf $TmpCaddyDir
fi

exit $exitCode
