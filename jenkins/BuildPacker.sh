#!/bin/bash
set -ex

export XLRDIR=${XLRDIR:-$PWD}
export XLRINFRADIR=${XLRINFRADIR:-$PWD/xcalar-infra}
export PATH=$XLRINFRADIR/bin:$XLRDIR/bin:$PATH
export REGISTRY=${REGISTRY:-$DEFAULT_REGISTRY}
REPO=${REPO:-xcalar/xcalar}

mkdir -p ${OUTDIR}

export PATH="$XLRINFRADIR/bin:$XLRDIR/bin:$PATH"

cd $XLRINFRADIR
. bin/activate

if [ -n "$EXECUTOR_NUMBER" ]; then
    git clean -fxd packer/
    docker rm $(docker ps -aq) || true

    if images=($(docker images --filter reference="${REGISTRY}/${REPO}:*" --format '{{.Repository}}:{{.Tag}}')); then
        docker rmi "${images[@]}" || true
    fi
fi

DIR=$(dirname ${XLRINFRADIR}/${PACKERCONFIG})
cd $DIR

eval $(installer-version.sh --format=sh $INSTALLER)

vault-auth-puppet-cert.sh
set -o pipefail
vault kv get -format=json -field=data secret/xcalar_licenses/cloud | jq -r '{license:.}' > license.json
export LICENSE_DATA=$PWD/license.json
cp ${OUTDIR}/*-manifest.json . || true
for BUILDER in ${BUILDERS//,/ }; do
    builder_osid="${BUILDER##*-}"
    builder_type="${BUILDER%%-*}"
    builder_name="${BUILDER#${builder_type}-}"
    builder_name="${builder_name%-$builder_osid}"
    if ! docker pull ${REGISTRY}/${builder_name}/base:${INSTALLER_VERSION}; then
        make ${builder_type}-base-${builder_osid} "INSTALLER=$INSTALLER" ${INSTALLER_URL:+"INSTALLER_URL=$INSTALLER_URL"} "REGISTRY=$REGISTRY"
    fi
    make $BUILDER "INSTALLER=$INSTALLER" ${INSTALLER_URL:+"INSTALLER_URL=$INSTALLER_URL"} "REGISTRY=$REGISTRY"
done
cp *-manifest.json ${OUTDIR}/ || true

exit 0
