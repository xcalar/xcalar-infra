#!/bin/bash
set -ex

export AWS_DEFAULT_REGION=us-west-2

EXIT_CODE=0
check_status() {
    STACKS=("$@")
    while true; do
        echo "Checking whether update was successful"
        NEW_STACK_LIST=(${STACKS[@]})
        for STACK in ${STACKS[@]}; do
            echo "Checking status for $STACK"
            STATUS=$(aws cloudformation describe-stacks --query "Stacks[?StackId==\`${STACK}\`].StackStatus" | jq -r .[0])
            if [ $STATUS == "UPDATE_COMPLETE" ] || [ $STATUS == "CREATE_COMPLETE" ]; then
                echo "$STACK is ready"
                DELETE=($STACK)
                L=${#NEW_STACK_LIST[@]}
                for (( i=0; i<$L; i++ )); do
                    if [[ ${NEW_STACK_LIST[$i]} = $DELETE  ]]; then
                        unset NEW_STACK_LIST[$i]
                    fi
                done
            elif [ $STATUS == "UPDATE_ROLLBACK_IN_PROGRESS" ] || [ $STATUS == "UPDATE_ROLLBACK_COMPLETE" ]; then
                echo "$STACK is faulty"
                EXIT_CODE=1
                DELETE=($STACK)
                L=${#NEW_STACK_LIST[@]}
                for (( i=0; i<$L; i++ )); do
                    if [[ ${NEW_STACK_LIST[$i]} = $DELETE  ]]; then
                        unset NEW_STACK_LIST[$i]
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
    echo "$1" | jq -r '.[][0].Parameters[] | select(.ParameterKey=="'$2'") | .ParameterValue'
}

if [ "${USERNAME_LIST}" == "ALL" ]; then
    STACK_LIST=$(aws cloudformation describe-stacks --query "Stacks[?starts_with(StackName, '${STACK_PREFIX}')]" | jq -r .[].StackId)
    if [ -z "$STACK_LIST"]; then
        echo "'$STACK_PREFIX' does not work"
        exit 1
    fi
elif [ "${USERNAME_LIST}" != "ALL" ] && ! [ -z "${USERNAME_LIST}" ]; then
    for USERNAME in ${USERNAME_LIST[@]}; do
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

for STACK in ${STACK_LIST[@]}; do
    RET=$(aws cloudformation describe-stacks --stack-name ${STACK})
    STATUS=$(echo $RET| jq -r .[][0].StackStatus)
    SIZE=$(get_stack_param "$RET" ClusterSize)
    if [ ${STATUS} == "UPDATE_COMPLETE" ] || [ ${STATUS} == "CREATE_COMPLETE" ]; then
        if [ -z "$SIZE" ]; then
            echo "Describe '${STACK}' doesn't have size"
            FAILURE_STACK_LIST+=("${STACK}")
            EXIT_CODE=1
        else
            CNAME=$(get_stack_param "$RET" CNAME)
            AUTHSTACKNAME=$(get_stack_param "$RET" AuthStackName)
            MAINSTACKNAME=$(get_stack_param "$RET" MainStackName)
            SESSIONTABLE=$(get_stack_param "$RET" SessionTable)
            if [ -z "$CNAME" ]; then
                CNAME_PARAMETER=''
            else
                CNAME_PARAMETER='ParameterKey=CNAME,UsePreviousValue=true'
            fi
            if [ -z "$AUTHSTACKNAME" ]; then
                AUTHSTACKNAME_PARAMETER=''
            else
                AUTHSTACKNAME_PARAMETER='ParameterKey=AuthStackName,UsePreviousValue=true'
            fi
            if [ -z "$SESSIONTABLE" ]; then
                SESSIONTABLE_PARAMETER=''
            else
                SESSIONTABLE_PARAMETER='ParameterKey=SessionTable,UsePreviousValue=true'
            fi
            if [ -z "${MAINSTACKNAME}" ]; then
                MAINSTACKNAME_PARAMETER=''
            else
                MAINSTACKNAME_PARAMETER='ParameterKey=MainStackName,UsePreviousValue=true'
            fi
            if [ $SIZE != 0 ]; then
                aws cloudformation update-stack --stack-name ${STACK} --use-previous-template \
                                                --parameters ParameterKey=ClusterSize,ParameterValue=0 \
                                                ${CNAME_PARAMETER} ${AUTHSTACKNAME_PARAMETER} ${SESSIONTABLE_PARAMETER} ${MAINSTACKNAME_PARAMETER} \
                                                --role-arn ${ROLE} \
                                                --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
            fi
        fi
    else
        FAILURE_STACK_LIST+=("${STACK}")
        echo "cannot update ${STACK}"
        EXIT_CODE=1
    fi
done

check_status "${STACK_LIST[@]}"

for STACK in ${STACK_LIST[@]}; do
    UPDATE_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK} | jq -r .[][0].StackStatus)
    if [ $UPDATE_STATUS == "UPDATE_COMPLETE" ]; then
        PREV_INFO=$(aws dynamodb get-item --table ${STACK_INFO_TABLE} \
                        --key '{"stack_id":{"S":"'"${STACK}"'"}}' | jq -r .Item.prev_info.S)
        if [ -z ${PREV_INFO} ] ||[ "${PREV_INFO}" == "null" ]; then
            NOT_ROLLBACK_STACKS+=(${STACK})
            EXIT_CODE=1
        else
            ROLLBACK_STACK_LIST+=("${STACK}")
            if [ "${LICENSE_TYPE}" == "dev" ]; then
                KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK_NAME}"'","licenseType":"Developer","compress":true,
                    "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
                    "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r .Compressed_Sig)
            elif [ "${LICENSE_TYPE}" == "prod" ]; then
                KEY=$(curl -d '{"secret":"xcalarS3cret","userId":"'"${STACK_NAME}"'","licenseType":"Production","compress":true,
                    "usercount":1,"nodecount":1025,"expiration":90,"licensee":"Xcalar, Inc","product":"Xcalar Data Platform",
                    "onexpiry":"Warn","jdbc":true}' -H "Content-type: application/json" -X POST "${LICENSE_ENDPOINT}" | jq -r.Compressed_Sig)
            else
                echo "Need to provide the licenseType"
                exit 1
            fi
            aws cloudformation update-stack --stack-name ${STACK} \
                                            --no-use-previous-template \
                                            ${PREV_INFO} ParameterKey=License,ParameterValue=${KEY} \
                                            --role-arn ${ROLE} \
                                            --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
            aws dynamodb update-item --table-name ${STACK_INFO_TABLE} \
                                --key '{"stack_id":{"S":"'"${STACK}"'"}}' \
                                --update-expression "SET #C = :c REMOVE prev_info"\
                                --expression-attribute-names '{"#C":"current_info"}' \
                                --expression-attribute-values '{":c":{"S":"'"${PREV_INFO}"'"}}'
        fi
    else
        FAILURE_STACK_LIST+=("${STACK}")
        EXIT_CODE=1
    fi
done

check_status "${ROLLBACK_STACK_LIST[@]}"
echo "${NOT_ROLLBACK_STACKS[@]} cannot rollback"
echo "cannot update stacks: ${FAILURE_STACK_LIST[@]}"

exit ${EXIT_CODE}
