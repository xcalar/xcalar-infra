#!/bin/bash
set -e
set -x

PRECHECKIN_VERIFY="${PRECHECKIN_VERIFY:-false}"
echo "PRECHECKIN_VERIFY: $PRECHECKIN_VERIFY"

RESULTS_DIR="${NETSTORE}/${JOB_NAME}/${BUILD_ID}"
echo "RESULTS_DIR: $RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
JDBC_PERF_OPTS="-n tpc_performance -o ${RESULTS_DIR}/tpc_performance"

MEM_DEBUGGER=${MemoryDebugger:-none}

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"
. $DIR/jenkinsUtils.sh
configFile="$XLRDIR/src/data/test.cfg"

onExit() {
    local retval=$?
    set +e
    (cd "$SPARK_DOCKER_DIR" && make clean)

    if [[ $retval != 0 ]]
    then
        genBuildArtifacts
        say "Build artifacts copied to ${NETSTORE}/${JOB_NAME}/${BUILD_ID}"
    fi

    (cd src/sqldf/ && git clean -fxd)
    exit $retval
}

test_jdbc() {
    ./src/sqldf/tests/test_jdbc.py $JDBC_TEST_OPTS $JDBC_PERF_OPTS -l -p "$XLRGUIDIR/assets/test/json/" -S $SPARK_IP "$@"
}

# the enclosing jenkins.sh now runs this script inside a virtualenv
# so no need to source xcsetenv
# we need xclean however, and that is not inherited
. doc/env/xc_aliases

if [ "${BUILD_ONCE}" != "1" ]; then
    cmBuild clean
    cmBuild config ${BUILD_TYPE:-debug}
    cmBuild xce

    cd $XLRGUIDIR
    # XXX ENG-6945 Revert this to make trunk once migration is done
    make trunk
cd ..
else
    echo >&2 "BUILD_ONCE set! Skipping building and configuring"
fi


JAVA_HOME=$(java_home.sh)
export JAVA_HOME
SPARK_DOCKER_DIR="$XLRDIR/docker/spark/master"

(cd "$SPARK_DOCKER_DIR" && make rm && make run)
trap onExit EXIT

SPARK_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' spark-master-jdbc)
echo "Spark JDBC server at $SPARK_IP"

# add configuration to default configuration file
# setting DecimalRescale to false(needed to compare results with spark)
echo "Constants.MoneyRescale=${MoneyAutoRescale:-false}" >> $configFile

# Some installers leave behind sqldf, expServer and other services running
# under supervisor, which causes respawn on kill and port conflicts
sudo pkill -f supervisord

# this should provide the SCALA_VERSION and SQLDF_VERSION
. "$XLRDIR"/src/3rd/spark/BUILD_ENV

SPARK_BRANCH="$(awk '{print $2}' "$XLRDIR"/src/3rd/spark/spark.txt)"
SPARK_VERSION="${SPARK_BRANCH##xcalar-spark-v}"

export SQLDF_VERSION SCALA_VERSION SPARK_VERSION

./bin/build-xcalar-sqldf.sh -j

xclean

GuardRailsArgs=${GuardRailsArgs:-}
declare -a XC2_ARGS=( "cluster" "start" "--num-nodes" "1" )

if [ "$MEM_DEBUGGER" = "guardrails" ]; then
    echo "Constants.NoChildLDPreload=true" >> $configFile

    # Increase the mmap map count for GuardRails to work
    echo 100000000 | sudo tee /proc/sys/vm/max_map_count

    # Build GuardRails
    make -C xcalar-infra/GuardRails clean
    make -C xcalar-infra/GuardRails deps
    make -C xcalar-infra/GuardRails

    XC2_ARGS+=("--guardrails-args" "$GuardRailsArgs")
fi

xc2 "${XC2_ARGS[@]}"

#./src/bin/usrnode/launcher.sh 1 daemon "$MEM_DEBUGGER"

timeOut=800
counter=0
set +e
until xccli -c "version" ; do
    find . -type f -name '*core*'
    ps -ef | grep gdbserver | grep -v grep
    sleep 5s

    counter=$(($counter + 5))
    if [ $counter -gt $timeOut ]; then
        say "usrnode time out"
        exit 1
    fi
done
set -e

source ./bin/nodes.sh
waitSqldf true ${MAX_SQLDF_WAIT_SEC}

LOGIN_JSON='{"xiusername": "admin", "xipassword": "admin"}'
curl -c cookiejar -H "Content-Type: application/json" -X POST -d "$LOGIN_JSON" "http://localhost:12124/login" || true

(cd src/sqldf/tests && ./test_sqldf.sh -u)

test_jdbc

echo "------------ START Parallelism Test ------------"
# xcTest is lightweight, so run 5 users to sanity test parallelism
test_jdbc -t test_xcTest -w5 -s1031
echo "------------  END Parallelism Test  ------------"

for jdbc_test_daily in $JDBC_TEST_DAILY; do
    test_jdbc -t $jdbc_test_daily
done
