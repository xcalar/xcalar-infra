#!/bin/bash
#
#

COMMIT=false
PUSH=false
REGISTRY=registry.int.xcalar.com
ALLOS="el6 el7 ub14 amzn1 amzn2"
IMAGEBASE=xcalar
OSEXTS=el7
SKIP_TESTS=false

usage() {
    echo >&2 "Repackage a node installer to only contain the desired OS, to reduce deploy/upload/download times"
    echo >&2
    echo >&2 "usage: $0 [-i <inpute-node-installer.sh>] [-o <output-basename>] [--osexts <comma sep list of platforms to extract (default: $OSEXTS)>]"
    echo >&2 "          [--skip-tests (don't test installer)] [--commit (commit test container)] [--push (push container)] [--upload <comma sep list of clouds to upload to>]"
    echo >&2
    echo >&2 "example: Extract EL7 and AMZN1 from xcalar-2.0.0-100-installer producing xcalar-2.0.0-installer-el7 and -amzn1"
    echo >&2 ' $ extract-installer.sh -i xcalar-2.0.0-100-installer --osexts el7,amzn1'
    exit 1
}

extract() {
    sed -n '/^__XCALAR_TARBALL__/,$p' "$1" | tail -n+2
}

extract_top() {
    sed -n '1,/^__XCALAR_TARBALL__$/p' "$1"
}

docker_clean() {
    docker images | grep "^${REGISTRY}/${IMAGEBASE}/xcalar" | awk '{printf "%s:%s\n",$1,$2}' | xargs -r -I{} -n1 docker rmi {}
}

docker_rpms() {
    docker run --rm "$1" bash -c 'rpm -qa | xargs -n1 -I{} rpm -q {} --qf "%{NAME}\n"' | sort
}

main() {
    local rc=0 cmd=''
    export http_proxy=${http_proxy-http://cacher:3128}
    if [ -n "$http_proxy" ] && curl -s -L $http_proxy | grep -q squid; then
        :
    else
        export http_proxy=
    fi
    while [ $# -gt 0 ]; do
        cmd="$1"
        shift
        case "$cmd" in
            --skip-tests) SKIP_TESTS=true;;
            -i|--installer) INSTALLER="$1"; shift;;
            --osexts|--osext) OSEXTS="$1"; shift;;
            -o|--output) OUTPUT="$1"; shift;;
            --commit) COMMIT=true;;
            --image) IMAGE="$1"; shift;;
            --push) COMMIT=true; PUSH=true;;
            --upload) UPLOAD="$1"; shift;;
            -h|--help) usage; exit 0;;
            *) usage; echo >&2 "ERROR: Unknown argument $cmd"; exit 1;;
        esac
    done
    if test -z "$INSTALLER"; then
        echo >&2 "ERROR: Must specify input (via -i <installer>)"
        usage
    fi
    if ! test -r "$INSTALLER"; then
        echo >&2 "ERROR: Unable to read $INSTALLER"
        usage
    fi
    INSTALLER="$(readlink -f "$INSTALLER")"
    BN="$(basename "$(readlink -f "$INSTALLER")")"
    VERSION_BUILD=($(echo $BN | grep -Eow '([0-9\.-]+)' | tr - ' '))
    VERSION=${VERSION_BUILD[0]}
    BUILD=${VERSION_BUILD[1]}
    if test -z "$OUTPUT"; then
        OUTPUT="${PWD}/$BN"
    fi

    export TMPDIR=${TMPDIR:-/tmp}/$(basename $0 .sh)-$(id -un)/$$
    rm -rf $TMPDIR
    mkdir -p $TMPDIR
    trap "rm -rf $TMPDIR" EXIT

    echo "Extracting original $INSTALLER ..." >&2
    extract_top "$INSTALLER" > $TMPDIR/xcalar-install-top.sh
    if test -e xcalar-install-top.sh.diff; then
        patch -d $TMPDIR --forward -p1 < xcalar-install-top.sh.diff >&2 || true
    fi
    extract "$INSTALLER" | tar zxf - -C $TMPDIR  >&2

    for OSEXT in $(echo $OSEXTS | tr ',' ' '); do
        EXCOS=(${ALLOS/$OSEXT/})
        INSTALLER_OSEXT="${OUTPUT}-${OSEXT}"
        echo "Extracting site-specific packages" >&2
        echo "Creating new archive ${INSTALLER_OSEXT} ..." >&2
        (cat $TMPDIR/xcalar-install-top.sh; tar czf - -C $TMPDIR . --exclude "*${EXCOS[0]}*" --exclude "*${EXCOS[1]}*" --exclude "*${EXCOS[2]}*" --transform=s,^./,,g) > "$INSTALLER_OSEXT".tmp \
            && mv "$INSTALLER_OSEXT".tmp -f "$INSTALLER_OSEXT" \
            && chmod 0555 "$INSTALLER_OSEXT"

        if [ -n "$UPLOAD" ]; then
            for REPO in ${UPLOAD//,/ }; do
                installer-url.sh -d $REPO "$INSTALLER_OSEXT"
            done
        fi
        if $SKIP_TESTS; then
            continue
        fi

        case $OSEXT in
            el6) IMAGE=centos:6 ;;
            el7)
                IMAGE=centos/systemd:latest
                CMD=
                ;;
            amzn1) IMAGE=ambakshi/amazon-linux:latest ;;
            *)
                echo >&2 "ERROR: Unknown image: $OSEXT"
                exit 1
                ;;
        esac
        BASE_RPMS="$(echo $IMAGE | sed -r 's,/,-,g; s,:,_,g').txt"
        if ! [ -e $BASE_RPMS ]; then
            docker_rpms $IMAGE > ${BASE_RPMS}.$$
            mv ${BASE_RPMS}.$$ $BASE_RPMS
        fi

        if ! docker image inspect xcalar-base-${OSEXT} > /dev/null 2>&1; then
            if [ $OSEXT == amzn1 ]; then
                cat > Dockerfile-${OSEXT} <<- EOF
				FROM $IMAGE
				RUN yum install -y http://repo.xcalar.net/xcalar-release-amzn1.rpm yum-plugin-fastestmirror && ACCEPT_EULA=Y yum install --enablerepo='xcalar-*' --disableplugin=priorities -y $(cat xcalar-${OSEXT}.txt | tr -d '\r' | tr '\n' ' ') curl && yum clean all --enablerepo='*' && rm -rf /var/cache/yum/*
				EOF
            else
                cat > Dockerfile-${OSEXT} <<- EOF
				FROM $IMAGE
				RUN yum install -y epel-release && yum install --enablerepo=epel --disableplugin=priorities -y $(cat xcalar-${OSEXT}.txt | tr -d '\r' | tr '\n' ' ') curl && yum clean all --enablerepo='*' && rm -rf /var/cache/yum/*
				EOF
            fi
            IMAGE=${REGISTRY}/${IMAGEBASE}/xcalar-base-${OSEXT}
            cat Dockerfile-${OSEXT}
            tar cf - Dockerfile-${OSEXT} xcalar-${OSEXT}.txt | docker build -t $IMAGE -f Dockerfile-${OSEXT} --build-arg=http_proxy=${http_proxy} -
        fi
        NAME=xcalar-${OSEXT}
        IMAGENAME=$REGISTRY/${IMAGEBASE}/${NAME}:${VERSION}-${BUILD}

        ## Test the installer
        docker rm -f $NAME || true
        docker run  --privileged \
                    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
                    --tmpfs /run \
                    --ulimit memlock=-1:-1 \
                    --shm-size=15g \
                    --name $NAME \
                    -d \
                    -e container=docker \
                    -e http_proxy \
                    -e TMPDIR \
                    -v $TMPDIR:$TMPDIR \
                    -v /tmp:/tmp \
                    -v ${PWD}:/host \
                    -w /host \
                    $IMAGE ${CMD-sleep inf} \
            && docker exec $NAME bash -c 'rpm -qa | xargs -n1 -I{} rpm -q {} --qf "%{NAME}\n"' | sort > xcalar-${VERSION}-${BUILD}-rpms-A.txt \
            && docker exec $NAME bash -x /tmp/$(basename $INSTALLER) --start \
            && docker exec $NAME bash -c 'rpm -qa | xargs -n1 -I{} rpm -q {} --qf "%{NAME}\n"' | sort > xcalar-${VERSION}-${BUILD}-rpms-B.txt

            comm -1 -3 xcalar-${VERSION}-${BUILD}-rpms-{A,B}.txt | grep -Ev '^(gpg-pubkey|xcalar|systemd)' > xcalar-${OSEXT}.txt || true
            echo "Output: $INSTALLER_OSEXT"
            echo "Listing: xcalar-${OSEXT}.txt"
            echo "Image: $IMAGE"
         rc=$?
        if [ $rc -ne 0 ]; then
            echo >&2 "ERROR: Failed to create installer $INSTALLER_OSEXT from $INSTALLER"
            return $rc
        fi
        if $COMMIT; then
            docker commit -m "From $1" -a "Xcalar, Inc" $NAME $IMAGENAME \
                && docker tag $IMAGENAME $NAME
            rc=$?
            if [ $rc -eq 0 ] && $PUSH; then
                docker push $IMAGENAME \
                    && echo >&2 "Finished pushing image $IMAGENAME"
                rc=$?
            fi
        fi
    done
    return $rc
}

main "$@"
