#!/bin/bash


export PATH=$XLRINFRADIR/bin:$PATH
if [ -z "$VIRTUAL_ENV" ]; then
    source $XLRINFRADIR/.venv/bin/activate
fi

source infra-sh-lib
source aws-sh-lib

failed() {
    declare -n store="${1}"
    declare stack=${!2}
    store+=([$stack]=FAILED)
    aws cloudformation delete-stack --stack-name $"stack"
}

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
PROJECT="$(basename "$(cd $DIR/.. && pwd)")"
PARMAS=parameters.json
export AWS_PAGER=''

declare -a TESTS=(params-with-efs.json params-with-eip.json params-with-eip-no-sg.json)

cd "$DIR"

declare -a TEST_STACKS=()
declare -A TEST_RESULTS
export BUILD_NUMMBER=${BUILD_NUMBER:-102}

TEST_BASE=cfntest

NTEST=1 #"${#TESTS[@]}"
for ii in $(seq 0 $((NTEST-1)) ); do
    tt=${TESTS[$ii]}

    TEST_NAME="$(basename $tt .json)"
    STACK_NAME="$(id -un)-${PROJECT}-${TEST_NAME}-${BUILD_NUMBER}"
    TEST_STACKS+=($STACK_NAME)

    if ! aws cloudformation validate-template --template-url "$URL"; then
        TEST_RESULTS[$STACK_NAME]=FAIL
        continue
    fi
    if ! aws cloudformation create-stack --template-url "$URL" --stack-name "$STACK_NAME" \
            --parameters file://"$(readlink -f $tt)"  \
            --tags Key=TestBase,Value=${TEST_BASE} \
                   Key=TestName,Value=${TEST_NAME} \
                   Key=BuildNumber,Value=${BUILD_NUMBER} \
                   Key=Owner,Value=$(git config user.email || $(id -un)) \
             --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND; then \
        TEST_RESULTS[$STACK_NAME]=FAIL
        continue
    fi
    GOOD_STACKS+=($STACK_NAME)
done
exit

GTESTS="${#GOOD_STACKS[@]}"
for ii in $(seq 0 $((GTESTS-1)) ); do

    STACK_NAME="${GOOD_STACKS[$ii]}"
    TEST_NAME="${STACK_NAME#${PROJECT}-}"
    TEST_NAME="${STACK_NAME%-${BUILD_NUMBER}}"

    if ! aws cloudformation wait stack-create-complete --stack-name $STACK_NAME; then
        aws cloudformation delete-stack --stack-name $STACK_NAME
        continue
    fi
    TEST_RESULTS[$STACK_NAME]=SUCCESS
done

echo "Waiting for keypress or 1h ..."
read -t 3600 FOO
for stack in "${TEST_STACKS[@]}"; do
    aws cloudformation delete-stack --stack-name $stack
done
for stack in "${TEST_STACKS[@]}"; do
    aws cloudformation wait stack-delete-complete --stack-name $stack
done





