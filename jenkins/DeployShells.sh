#!/bin/bash
#
# shellcheck disable=SC1091,SC2086

set -ex
export AWS_DEFAULT_REGION=us-west-2
export XLRINFRADIR=${XLRINFRADIR:-$PWD}
export PATH=$XLRINFRADIR/bin:/opt/xcalar/bin:$HOME/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin:$PATH

generate_key() {
    if [ "${LICENSE_TYPE}" == "dev" ]; then
        KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK}${SUFFIX}"'","licenseType":"Developer","compress":true,
            "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
            "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r .Compressed_Sig)
    elif [ "${LICENSE_TYPE}" == "prod" ]; then
        KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK}"'","licenseType":"Production","compress":true,
            "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
            "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r .Compressed_Sig)
    else
        echo "Need to provide the licenseType"
        exit 1
    fi
    echo "${KEY}"
}

EXIT_CODE=0

get_stack_param() {
    echo "$1" | jq -r '.[][0].Parameters[] | select(.ParameterKey=="'$2'") | .ParameterValue'
}

mapfile -t AVAILABLE_STACKS < <(aws cloudformation describe-stacks --query "Stacks[?Tags[?Key=='available']]" | jq -r .[].StackId)
NUM_AVAIL=${#AVAILABLE_STACKS[@]}
if [ $NUM_AVAIL -lt $TOTAL_AVAIL ]; then
    NUM_TO_CREATE=$(expr $TOTAL_AVAIL - $NUM_AVAIL)
    echo "Creating ${NUM_TO_CREATE} stacks"
    for i in `seq 1 $NUM_TO_CREATE`; do
        echo "Creating stack ${i}"
        SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 10 | head -n 1)
        #KEY_VAL=$(generate_key)
        CNAME=$(cat /dev/urandom | tr -dc 'a-z1-9' | fold -w 4 | head -n 1)
        URL_PARAMS=(--template-url ${CFN_TEMPLATE_URL}
                        --parameters ParameterKey=ClusterSize,ParameterValue=${STARTING_CLUSTER_SIZE}
                                    ParameterKey=CNAME,ParameterValue=${CNAME}
                                    ParameterKey=SessionTable,ParameterValue=${SESSION_TABLE}
                                    ParameterKey=AuthStackName,ParameterValue=${AUTH_STACK_NAME}
                                    ParameterKey=MainStackName,ParameterValue=${MAIN_STACK_NAME}
                                    ParameterKey=AllowedCIDR,ParameterValue='0.0.0.0/0'
                                    ParameterKey=HostedZoneName,ParameterValue=${HOSTED_ZONE_NAME}
                                    ParameterKey=AdminUsername,ParameterValue=${ADMIN_USERNAME}
                                    ParameterKey=AdminPassword,ParameterValue=${ADMIN_PASSWORD})
        RET=$(aws cloudformation create-stack \
        --role-arn "${ROLE}" \
        --stack-name "${STACK_PREFIX}${SUFFIX}" "${URL_PARAMS[@]}" \
        --tags Key=available,Value=true \
                Key=deployment,Value=saas \
        --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND)
        STACK_ID=$(echo $RET | jq -r .StackId)
        if [ -z ${STACK_ID} ]; then
            echo "create '${STACK_ID}' failes"
            EXIT_CODE=1
        else
            STACK_LIST+=( "${STACK_ID}" )
            aws dynamodb put-item --table-name ${STACK_INFO_TABLE} \
                                --item '{
                                    "stack_id": {"S": "'"${STACK_ID}"'"},
                                    "current_info": {"S": "'"${URL_PARAMS[*]}"'"}
                                    }'
        fi
    done
fi
#comment it out: may need it to only update license
#for STACK in ${AVAILABLE_STACKS[@]}; do
#    RET=$(aws cloudformation describe-stacks --stack-name ${STACK})
#    UPDATE_STATUS=$(echo $RET| jq -r .[][0].StackStatus)
#    CNAME=$(echo $RET | jq -r '.[][0].Parameters[] | select(.ParameterKey=="CNAME") | .ParameterValue')
#    CNAME=$(get_stack_param "$RET" CNAME)
#    IMAGE_ID=$(get_stack_param "$RET" ImageId)
#    if [ "${IMAGE_ID}" != "${AMI}" ]; then
#        if [ $UPDATE_STATUS == "UPDATE_COMPLETE" ] || [ $UPDATE_STATUS == "CREATE_COMPLETE" ]; then
#            STACK_NAME=$(echo ${STACK} | cut -d "/" -f 2)
#            STACK_LIST+=("${STACK}")
#            if [ -z "$CNAME" ]; then
#                CNAME=$(cat /dev/urandom | tr -dc 'a-z1-9' | fold -w 4 | head -n 1)
#            fi
#            KEY_VAL=$(generate_key)
#            URL_PARAMS="--template-url ${CFN_TEMPLATE_URL} \
#                        --parameters ParameterKey=ClusterSize,ParameterValue=${STARTING_CLUSTER_SIZE} \
#                                    ParameterKey=CNAME,ParameterValue=${CNAME} \
#                                    ParameterKey=SessionTable,ParameterValue=${SESSION_TABLE} \
#                                    ParameterKey=AuthStackName,ParameterValue=${AUTH_STACK_NAME} \
#                                    ParameterKey=MainStackName,ParameterValue=${MAIN_STACK_NAME} \
#                                    ParameterKey=AllowedCIDR,ParameterValue='0.0.0.0/0' \
#                                    ParameterKey=HostedZoneName,ParameterValue=${HOSTED_ZONE_NAME} \
#                                    ParameterKey=AdminUsername,ParameterValue=${ADMIN_USERNAME} \
#                                    ParameterKey=AdminPassword,ParameterValue=${ADMIN_PASSWORD}"
#            aws cloudformation update-stack --stack-name ${STACK} \
#                                            --no-use-previous-template \
#                                           ${URL_PARAMS} \
#                                            --role-arn ${ROLE} \
#                                            --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
#            aws dynamodb put-item --table-name ${STACK_INFO_TABLE} \
#                                --item '{
#                                    "stack_id": {"S": "'"${STACK}"'"},
#                                    "current_info": {"S": "'"${URL_PARAMS}"'"}
#                                    }'
#        else
#            FAILURE_STACK_LIST+=("${STACK}")
#            echo "cannot update ${STACK}"
#            EXIT_CODE=1
#        fi
#    fi
#done

while true; do
    echo "Checking whether creation was successful"
    NEW_STACK_LIST=("${STACK_LIST[@]}")
    for STACK in "${STACK_LIST[@]}"; do
        echo "Checking status for $STACK"
        STATUS=$(aws cloudformation describe-stacks --query "Stacks[?StackId==\`${STACK}\`].StackStatus" | jq -r .[0])
        if [ $STATUS = "CREATE_COMPLETE" ] || [ $STATUS = "UPDATE_COMPLETE" ]; then
            echo "$STACK is ready"
            L=${#NEW_STACK_LIST[@]}
            for (( i=0; i<$L; i++ )); do
                if [ "${NEW_STACK_LIST[$i]}" = "${STACK}" ]; then
                    unset 'NEW_STACK_LIST[$i]'
                fi
            done
        elif [ $STATUS = "ROLLBACK_IN_PROGRESS" ] || [ $STATUS = "ROLLBACK_COMPLETE" ] || [ $STATUS = "UPDATE_ROLLBACK_COMPLETE" ] || [ $STATUS = "UPDATE_ROLLBACK_IN_PROGRESS" ]; then
            echo "$STACK is faulty"
            EXIT_CODE=1
            L=${#NEW_STACK_LIST[@]}
            for (( i=0; i<$L; i++ )); do
                if [ ${NEW_STACK_LIST[$i]} = "${STACK}" ]; then
                    unset 'NEW_STACK_LIST[$i]'
                fi
            done
            FAILURE_STACK_LIST+=("${STACK}")
        else
            STATUS=$(aws cloudformation describe-stacks --query "Stacks[?StackId==\`${STACK}\`].StackStatus" | jq .[0])
            echo "$STACK is not ready. Status: $STATUS"
        fi

        echo "${STACK}"
        echo "${NEW_STACK_LIST[@]}"
        echo "${STACK_LIST[@]}"
    done
    if [ ${#NEW_STACK_LIST[@]} -eq 0 ]; then
        echo "All stacks ready!"
        echo "Stacks: ${FAILURE_STACK_LIST[*]} under rollback status"
        exit ${EXIT_CODE}
    fi

    STACK_LIST=("${NEW_STACK_LIST[@]}")
    sleep 15
done
