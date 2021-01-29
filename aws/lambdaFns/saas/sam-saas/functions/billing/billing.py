import boto3
import json
import time
import traceback
import re
import os

from enums.status_enum import Status
from util.http_util import _http_status, _make_reply, _make_options_reply, _replace_headers_origin
from util.user_util import get_user_info, reset_user_cfn, validate_user_instance, check_user_credential
from util.cfn_util import get_stack_info
from util.billing_util import get_price
# To-do all hard-coded values need to be read from enviornemnt variables
region = os.environ.get('REGION')
dynamodb_client = boto3.client('dynamodb', region_name=region)
cfn_client = boto3.client('cloudformation', region_name=region)
ec2_client = boto3.client('ec2', region_name=region)

domain = os.environ.get('DOMAIN')
user_table = os.environ.get('USER_TABLE')
billing_table = os.environ.get('BILLING_TABLE')
session_table = os.environ.get('SESSION_TABLE')
creds_table = os.environ.get('CREDS_TABLE')


def get_credit(user_name):
    response = dynamodb_client.query(
        TableName=billing_table,
        ScanIndexForward=True,
        ProjectionExpression='credit_change',
        KeyConditionExpression='user_name = :uname',
        ExpressionAttributeValues={
            ':uname': {
                'S': user_name
            }
        }
    )
    credit = 0
    if 'Items' in response and len(response['Items']) > 0:
        for row in response['Items']:
            credit += float(row['credit_change']['N'])
    else:
        return _make_reply(_http_status(response), {
            'status': Status.NO_CREDIT_HISTORY,
            'error': 'No credit history for user: %s' % user_name
        })

    while 'LastEvaluatedKey' in response:
        response = dynamodb_client.query(
            TableName=billing_table,
            ScanIndexForward=True,
            ExclusiveStartKey=response['LastEvaluatedKey'],
            ProjectionExpression='credit_change',
            KeyConditionExpression='user_name = :uname',
            ExpressionAttributeValues={
                ':uname': {
                    'S': user_name
                }
            }
        )
        if 'Items' in response and len(response['Items']) > 0:
            for row in response['Items']:
                credit += float(row['credit_change']['N'])
    return _make_reply(_http_status(response), {
        'status': Status.OK,
        'credits': credit,
    })

def update_credit(user_name, credit_change):
    transaction = {
        'user_name': {
            'S': user_name
        },
        'timestamp': {
            'N': str(round(time.time() * 1000))
        },
        'credit_change': {
            'N': credit_change
        }
    }
    response = dynamodb_client.put_item(
        TableName=billing_table,
        Item=transaction
    )
    return _make_reply(_http_status(response), {
        'status': Status.OK
    })

def deduct_credit(user_name):
    # For expServer to invoke - it only has access to deduct credit.
    # No other configurable params - to avoid potential securty issue with juypter
    # To-do auth logic to make sure the caller is updating his credit only
    user_info = get_user_info(dynamodb_client, user_name, user_table)
    if 'Item' in user_info and 'cfn_id' in user_info['Item']:
        cfn_id = user_info['Item']['cfn_id']['S']
    else:
        return _make_reply(_http_status(user_info), {
            'status': Status.NO_STACK,
            'error': '%s does not have a stack' % user_name
        })
    stack_info = get_stack_info(cfn_client, cfn_id)
    if 'errorCode' in stack_info:
        return _make_reply(stack_info['errorCode'], {
            'status': Status.STACK_NOT_FOUND,
            'error': 'Stack %s not found' % cfn_id
        })
    elif 'size' not in stack_info or 'type' not in stack_info or stack_info['size'] == 0:
        return _make_reply(200, {
            'status': Status.NO_RUNNING_CLUSTER,
            'error': 'No running cluster'
        })
    credit_change = str(-1 * get_price(stack_info['type'], stack_info['size']))
    return update_credit(user_name, credit_change)

def lambda_handler(event, context):
    try:
        path = event['path']
        headers = event['headers']
        headers_origin = '*'
        headers_cookies = None
        for key, headerLine in headers.items():
            if (key.lower() == "origin"):
                headers_origin = headerLine
            if (key.lower() == "cookie"):
                headers_cookies = headerLine
        if headers_origin == '*':
            data = json.loads(event['body'])
            if 'username' not in data or \
               'instanceId' not in data or \
               validate_user_instance(ec2_client,
                                      data['username'],
                                      data['instanceId']) != True:
                return _make_reply(401, {
                    'status': Status.AUTH_ERROR,
                    'error': 'Authentication failed'
                }, headers_origin)
        elif re.match('^https://\w+.'+domain, headers_origin, re.M|re.I):
            if (event['httpMethod'] == 'OPTIONS'):
                return _make_options_reply(200,  headers_origin)
            data = json.loads(event['body'])
            credential, username = check_user_credential(dynamodb_client,
                                                         session_table,
                                                         creds_table,
                                                         headers_cookies)
            if credential is None or (username != data['username'] and \
                                      path != '/billing/update' and \
                                      path != '/billing/get'):
                return _make_reply(401, {
                    'status': Status.AUTH_ERROR,
                    'error': "Authentication Failed"
                }, headers_origin)
        else:
            return _make_reply(403, "Forbidden",  headers_origin)

        if path == '/billing/get':
            reply = get_credit(data['username'])
        elif path == '/billing/update':
            reply = update_credit(data['username'], data['creditChange'])
        elif path == '/billing/deduct':
            reply = deduct_credit(data['username'])
        else:
            reply = _make_reply(400, "Invalid endpoint: %s" % path)
    except Exception as e:
        traceback.print_exc()
        reply = _make_reply(400, "Exception has occurred: {}".format(e))
    reply = _replace_headers_origin(reply, headers_origin)
    return reply
