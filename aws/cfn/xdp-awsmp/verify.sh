#!/bin/bash

. infra-sh-lib
. aws-sh-lib

ok() {
    echo "ok $ti ${1:+- $1}"
    ((ti++))
}

not_ok() {
    echo "not ok $ti ${1:+- $1}"
    ((ti++))
}

checkbootstrap() {
    ti=1
    echo "TAP 1.3"
    echo "1..6"
    if ! templatebootstrapUrl="$(jq -r "'.${bootstrapPath}'" < $templateJson)"; then
        not_ok "template $templateJson is missing bootstrapUrl=$bootstrapUrl in $bootstrapPath"
    else
        ok "bootstrapUrl is in template"
    fi
    if test -z "$templatebootstrapUrl" || [ "$templatebootstrapUrl" = "null" ]; then
        not_ok "template bootstrapUrl is null"
    else
        ok "template bootstrapUrl is $templatebootstrapUrl"
    fi
    if ! check_url "$templatebootstrapUrl"; then
        not_ok "template bootstrapUrl=$templatebootstrapUrl doesn't exist"
    else
        ok "bootstrapUrl $templatebootstrapUrl exists"
    fi
    amzn1ami="$(jq -r ".${mappingsPath}.AMZN1HVM" < $templateJson)"
    if test -z "$amzn1ami" || [ "$amzn1ami" = "null" ]; then
        not_ok "amzn1ami is null"
    else
        ok "amzn1ami is $amzn1ami"
    fi
    if [ "$amzn1ami" != "$ami_id" ]; then
        not_ok "amzn1ami != $ami_id"
    else
        ok "amzn1ami = $ami_id"
    fi
}

main() {
    region="${AWS_DEFAULT_REGION:-us-west-2}"
    bootstrapPath='Resources.LaunchTemplate.Metadata."AWS::CloudFormation::Init".configure_app.files["/var/lib/cloud/instance/bootstrap.sh"].source'

    while [ $# -gt 0 ]; do
        local cmd="$1"
        case "$cmd" in
            -h|--help) usage; exit 0;;
            --ami-id) ami_id="$1"; shift;;
            --template) templateJson="$1"; shift;;
            --bootstrap-url) bootstrapUrl="$1"; shift;;
            --region) region="$1"; shift;;
            --) break;;
            -*) usage >&2; die "Unknown parameter $cmd";;
        esac
    done
    if [ -z "$mappingsPath" ]; then
        mappingsPath="Mappings.AWSAMIRegionMap.AMI.\"${region}\""
    fi
    checkbootstrap "$@"
}

main "$@"
