#!/bin/bash

set -ex

export AWS_DEFAULT_REGION=us-west-2
export XLRINFRADIR=${XLRINFRADIR:-$PWD}
#have user name list, need find the stack id via tag
#username list is ALL, update all
EXIT_CODE=0
check_status() {
    STACKS=("$@")
    while true; do
        echo "Checking whether update was successful"
        NEW_STACK_LIST=("${STACKS[@]}")
        for STACK in "${STACKS[@]}"; do
            echo "Checking status for $STACK"
            STATUS=$(aws cloudformation describe-stacks --query "Stacks[?StackId==\`${STACK}\`].StackStatus" | jq -r .[0])
            if [ "${STATUS}" = "UPDATE_COMPLETE" ] || [ "${STATUS}" = "CREATE_COMPLETE" ]; then
                echo "$STACK is ready"
                L=${#NEW_STACK_LIST[@]}
                for (( i=0; i<$L; i++ )); do
                    if [ ${NEW_STACK_LIST["${i}"]} = "${STACK}" ]; then
                        unset 'NEW_STACK_LIST[$i]'
                    fi
                done
            elif [ "${STATUS}" = "UPDATE_ROLLBACK_IN_PROGRESS" ] || [ "${STATUS}" = "UPDATE_ROLLBACK_COMPLETE" ]; then
                echo "${STACK} is faulty"
                EXIT_CODE=1
                L=${#NEW_STACK_LIST[@]}
                for (( i=0; i<$L; i++ )); do
                    if [ ${NEW_STACK_LIST[$i]} = "${STACK}" ]; then
                        unset 'NEW_STACK_LIST[$i]'
                    fi
                done
                FAILURE_STACK_LIST+=("${STACK}")
            else
                echo "$STACK is not ready. Status: $STATUS"
            fi

            echo "$STACK"
            echo "${NEW_STACK_LIST[@]}"
            echo "${STACKS[@]}"
        done
        if [ ${#NEW_STACK_LIST[@]} -eq 0 ]; then
            echo "All stacks ready!"
            break;
        fi

        STACKS=("${NEW_STACK_LIST[@]}")
        sleep 15
    done
}

get_stack_param() {
    echo "$1" | jq -r '.[][0].Parameters[] | select(.ParameterKey=="'"$2"'") | .ParameterValue'
}

get_stack_tag() {
    echo "$1" | jq -r '.[][0].Tags[] | select(.Key=="'"$2"'") | .Value'
}

if [ "${USERNAME_LIST}" == "ALL" ]; then
    mapfile -t STACK_LIST < <(aws cloudformation describe-stacks --query "Stacks[?starts_with(StackName, '${STACK_PREFIX}')]" | jq -r .[].StackId)
    if [ -z "${STACK_LIST[@]}" ]; then
        echo "'$STACK_PREFIX' does not work"
        exit 1
    fi
elif [ "${USERNAME_LIST}" != "ALL" ] && ! [ -z "${USERNAME_LIST}" ]; then
    IFS=" " read -r -a USERNAME_ARRAY <<< "$(echo "${USERNAME_LIST}")"
    for USERNAME in "${USERNAME_ARRAY[@]}"; do
        RET=$(aws cloudformation describe-stacks --query "Stacks[?Tags[?Value=='${USERNAME}']]" | jq -r .[].StackId)
        if [ -z "$RET" ]; then
            echo "'$USERNAME' doesn't have stack"
            EXIT_CODE=1
        else
            STACK_LIST+=("$RET")
        fi
    done
else
    echo "Need to Specific USERNAME_LIST"
    exit 1
fi

for STACK in "${STACK_LIST[@]}"; do
    RET=$(aws cloudformation describe-stacks --stack-name "${STACK}")
    STATUS=$(echo "${RET}"| jq -r .[][0].StackStatus)
    SIZE=$(get_stack_param "$RET" ClusterSize)
    if [ "${STATUS}" = "UPDATE_COMPLETE" ] || [ "${STATUS}" = "CREATE_COMPLETE" ]; then
        if [ -z "$SIZE" ]; then
            echo "Describe '${STACK}' doesn't have size"
            FAILURE_STACK_LIST+=("${STACK}")
            EXIT_CODE=1
        else
            UPDATE_STACK_LIST+=("${STACK}")
            if [ "${SIZE}" != 0 ]; then
                CHECKED_STACK_LIST+=("${STACK}")
                CNAME_CURRENT=$(get_stack_param "$RET" CNAME)
                AUTHSTACKNAME_CURRENT=$(get_stack_param "$RET" AuthStackName)
                MAINSTACKNAME_CURRENT=$(get_stack_param "$RET" MainStackName)
                SESSIONTABLE_CURRENT=$(get_stack_param "$RET" SessionTable)
                ALLOWEDCIDR_CURRENT=$(get_stack_param "$RET" AllowedCIDR)
                HOSTEDZONENAME_CURRENT=$(get_stack_param "$RET" HostedZoneName)
                ADMINUSERNAME_CURRENT=$(get_stack_param "$RET" AdminUsername)
                ADMINPASSWORD_CURRENT=$(get_stack_param "$RET" AdminPassword)
                if [ -z "${CNAME_CURRENT}" ]; then
                    CNAME_PARAMETER=''
                else
                    CNAME_PARAMETER='ParameterKey=CNAME,UsePreviousValue=true'
                fi
                if [ -z "${AUTHSTACKNAME_CURRENT}" ]; then
                    AUTHSTACKNAME_PARAMETER=''
                else
                    AUTHSTACKNAME_PARAMETER='ParameterKey=AuthStackName,UsePreviousValue=true'
                fi
                if [ -z "${MAINSTACKNAME_CURRENT}" ]; then
                    MAINSTACKNAME_PARAMETER=''
                else
                    MAINSTACKNAME_PARAMETER='ParameterKey=MainStackName,UsePreviousValue=true'
                fi
                if [ -z "${SESSIONTABLE_CURRENT}" ]; then
                    SESSIONTABLE_PARAMETER=''
                else
                    SESSIONTABLE_PARAMETER='ParameterKey=SessionTable,UsePreviousValue=true'
                fi
                if [ -z "${ALLOWEDCIDR_CURRENT}" ]; then
                    ALLOWEDCIDR_PARAMETER=''
                else
                    ALLOWEDCIDR_PARAMETER='ParameterKey=AllowedCIDR,UsePreviousValue=true'
                fi
                if [ -z "${HOSTEDZONENAME_CURRENT}" ]; then
                    HOSTEDZONENAME_PARAMETER=''
                else
                    HOSTEDZONENAME_PARAMETER='ParameterKey=HostedZoneName,UsePreviousValue=true'
                fi
                if [ -z "${ADMINUSERNAME_CURRENT}" ]; then
                    ADMINUSERNAME_PARAMETER=''
                else
                    ADMINUSERNAME_PARAMETER='ParameterKey=AdminUsername,UsePreviousValue=true'
                fi
                if [ -z "${ADMINPASSWORD_CURRENT}" ]; then
                    ADMINPASSWORD_PARAMETER=''
                else
                    ADMINPASSWORD_PARAMETER='ParameterKey=AdminPassword,UsePreviousValue=true'
                fi
                aws cloudformation update-stack --stack-name "${STACK}" --use-previous-template \
                                                --parameters ParameterKey=ClusterSize,ParameterValue=0 \
                                                ParameterKey=InstanceType,UsePreviousValue=true \
                                                ${CNAME_PARAMETER} \
                                                ${AUTHSTACKNAME_PARAMETER} \
                                                ${MAINSTACKNAME_PARAMETER} \
                                                ${SESSIONTABLE_PARAMETER} \
                                                ${ALLOWEDCIDR_PARAMETER} \
                                                ${HOSTEDZONENAME_PARAMETER} \
                                                ${ADMINUSERNAME_PARAMETER} \
                                                ${ADMINPASSWORD_PARAMETER} \
                                                --role-arn "${ROLE}" \
                                                --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
            fi
        fi
    else
        FAILURE_STACK_LIST+=("${STACK}")
        echo "cannot update ${STACK}"
        EXIT_CODE=1
    fi
done

check_status "${CHECKED_STACK_LIST[@]}"

for STACK in "${UPDATE_STACK_LIST[@]}"; do
    #STACK_NAME=$(echo ${STACK} | cut -d "/" -f 2)
    RET=$(aws cloudformation describe-stacks --stack-name "${STACK}")
    UPDATE_STATUS=$(echo "$RET"| jq -r .[][0].StackStatus)
    CNAME=$(get_stack_param "$RET" CNAME)
    if [ "${UPDATE_STATUS}" = "UPDATE_COMPLETE" ] || [ "${UPDATE_STATUS}" = "CREATE_COMPLETE" ]; then
        UPDATED_STACK_LIST+=("${STACK}")
        if [ -z "$CNAME" ]; then
            CNAME=$(cat /dev/urandom | tr -dc 'a-z1-9' | fold -w 4 | head -n 1)
        fi
        #if [ "${LICENSE_TYPE}" == "dev" ]; then
        #    KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK_NAME}"'","licenseType":"Developer","compress":true,
        #        "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
        #        "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r .Compressed_Sig)
        #elif [ "${LICENSE_TYPE}" == "prod" ]; then
        #    KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK_NAME}"'","licenseType":"Production","compress":true,
        #        "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
        #        "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r .Compressed_Sig)
        #else
        #    echo "Need to provide the licenseType"
        #    exit 1
        #fi
        CURRENT_INFO=$(aws dynamodb get-item --table "${STACK_INFO_TABLE}" \
                        --key '{"stack_id":{"S":"'"${STACK}"'"}}' | jq -r .[].current_info.S)
        if [[ "${CURRENT_INFO}" != *"${CFN_TEMPLATE_URL}"* ]]; then
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
            OWNER=$(get_stack_tag "$RET" Owner)
            DEPLOYMENT=$(get_stack_tag "$RET" deployment)
            if [ "$IS_TEST_CLUSTER" = "true" ]; then
                aws cloudformation update-stack --stack-name "${STACK}" \
                                                --no-use-previous-template \
                                                "${URL_PARAMS[@]}" --tags Key=Owner,Value="${OWNER}" Key=deployment,Value=${DEPLOYMENT} Key=Env,Value=test \
                                                --role-arn "${ROLE}" \
                                                --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
            else
                aws cloudformation update-stack --stack-name "${STACK}" \
                                                --no-use-previous-template \
                                                "${URL_PARAMS[@]}" --tags Key=Owner,Value="${OWNER}" Key=deployment,Value=${DEPLOYMENT} \
                                                --role-arn "${ROLE}" \
                                                --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
            fi
            PREV_INFO=$(aws dynamodb get-item --table "${STACK_INFO_TABLE}" \
                        --key '{"stack_id":{"S":"'"${STACK}"'"}}' | jq -r .Item.current_info.S)
            #Assue only template url and iamge id will change.
            #If image id won't change, that means we only update license key
            #will add more check
            if [ -z "${PREV_INFO}" ]; then
                aws dynamodb put-item --table-name "${STACK_INFO_TABLE}" \
                                --item '{
                                    "stack_id": {"S": "'"${STACK}"'"},
                                    "current_info": {"S": "'"${URL_PARAMS[*]}"'"}
                                    }'
            else
                aws dynamodb update-item --table-name "${STACK_INFO_TABLE}" \
                                    --key '{"stack_id":{"S":"'"${STACK}"'"}}' \
                                    --update-expression "SET #P = :p, #C = :c" \
                                    --expression-attribute-names '{"#P":"prev_info", "#C":"current_info"}' \
                                    --expression-attribute-values '{":p":{"S":"'"${PREV_INFO}"'"},
                                                                    ":c":{"S":"'"${URL_PARAMS[*]}"'"}}'
            fi
        else
            echo "${STACK} is up to date"
        fi
    else
        echo "cannot update ${STACK}"
        EXIT_CODE=1
    fi
done

check_status "${UPDATED_STACK_LIST[@]}"
echo "cannot update stacks: ${FAILURE_STACK_LIST[*]}"

exit ${EXIT_CODE}
