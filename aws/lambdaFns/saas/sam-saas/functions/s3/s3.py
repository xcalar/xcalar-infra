import boto3
import json
import traceback
import re
import os
from enums.status_enum import Status
from util.http_util import _http_status, _make_reply, _make_options_reply, _replace_headers_origin
from util.cfn_util import get_stack_info
from util.user_util import get_user_info, check_user_credential

# Intialize all service clients
region = os.environ.get('REGION')
cfn_client = boto3.client('cloudformation', region_name=region)
dynamodb_client = boto3.client('dynamodb', region_name=region)
domain = os.environ.get('DOMAIN')
user_table = os.environ.get('USER_TABLE')
session_table = os.environ.get('SESSION_TABLE')
creds_table = os.environ.get('CREDS_TABLE')

def get_bucket(user_name):
    response = get_user_info(dynamodb_client, user_name, user_table)
    if 'Item' not in response:
        return _make_reply(_http_status(response), {
            'status': Status.USER_NOT_FOUND,
            'error': "%s does not exist" % user_name
        })
    cfn_id = response['Item']['cfn_id']['S']
    stack_info = get_stack_info(cfn_client, cfn_id)
    if 'errorCode' in stack_info:
        return _make_reply(stack_info['errorCode'], {
            'status': Status.STACK_NOT_FOUND,
            'error': 'Stack %s not found' % cfn_id
        })
    if 's3_url' not in stack_info:
        return _make_reply(200, {
            'status': Status.S3_BUCKET_NOT_EXIST,
            'error': 'Cloud not find s3 given stack %s' % cfn_id
        })
    return stack_info['s3_url']

def get_upload_file_url(upload_params):
    user_name = upload_params['username']
    file_name = upload_params['fileName']
    fields = upload_params['fields']
    conditions = upload_params['conditions']
    bucket_resp = get_bucket(user_name)
    if type(bucket_resp) != str:
        return bucket_resp
    expiration = 3600
    s3_client = boto3.client('s3', region_name=region)
    res_dict = s3_client.generate_presigned_post(bucket_resp, file_name, Fields=fields, Conditions=conditions, ExpiresIn=expiration)
    return _make_reply(200, {
        'status': Status.OK,
        'responseDict': res_dict
    })

def delete_file(delete_params):
    user_name = delete_params['username']
    file_name = delete_params['fileName']
    bucket_resp = get_bucket(user_name)
    if type(bucket_resp) != str:
        return bucket_resp
    s3_client = boto3.client('s3', region_name=region)
    s3_client.delete_object(Bucket=bucket_resp, Key=file_name)
    return _make_reply(200, {
        'status': Status.OK
    })

def bucket_info(user_name):
    bucket_resp = get_bucket(user_name)
    if type(bucket_resp) != str:
        return bucket_resp
    return _make_reply(200, {
        'status': Status.OK,
        'bucketName': bucket_resp
    })

def put_cors_config(user_name):
    # Hard code it here
    cors_config = {
		"CORSRules": [
            {
                "AllowedHeaders": ["*"],
                "AllowedMethods": ["POST"],
                "AllowedOrigins": ["*"],
                "MaxAgeSeconds": 3000
            }
        ]
	}
    bucket_resp = get_bucket(user_name)
    if type(bucket_resp) != str:
        return bucket_resp
    s3_client = boto3.client('s3', region_name=region)
    s3_client.put_bucket_cors(Bucket=bucket_resp, CORSConfiguration=cors_config)
    return _make_reply(200, {
        'status': Status.OK
    })

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
        if re.match('^https://\w+.'+domain, headers_origin, re.M|re.I):
            if (event['httpMethod'] == 'OPTIONS'):
                return _make_options_reply(200,  headers_origin)

            data = json.loads(event['body'])
            credential, username = check_user_credential(dynamodb_client,
                                                         session_table,
                                                         creds_table,
                                                         headers_cookies)
            if credential == None or username != data['username']:
                return _make_reply(401, {
                    'status': Status.AUTH_ERROR,
                    'error': "Authentication Failed"
                },
                headers_origin)
        else:
            return _make_reply(403, {
                'error': "Forbidden"
            },
            headers_origin)

        if path == '/s3/uploadurl':
            reply = get_upload_file_url(data)
        elif path == '/s3/delete':
            reply = delete_file(data)
        elif path == '/s3/describe':
            reply = bucket_info(data['username'])
        elif path == '/s3/corsconfig':
            reply = put_cors_config(data['username'])
        else:
            reply = _make_reply(400, {
                'error': "Invalid endpoint: %s" % path
            })

    except Exception as e:
        traceback.print_exc()
        reply = _make_reply(400, {
            'error': "Exception has occurred: {}".format(e)
        })
    reply = _replace_headers_origin(reply, headers_origin)
    return reply
