#!/usr/bin/env python3
import os
import sys
import json
import requests
import boto3

this_dir = os.path.dirname(os.path.abspath(__file__))
discover_dir = os.path.abspath(os.path.join(this_dir, '..', 'discover'))
sys.path.insert(0, discover_dir)

import aws_helper

STACK_NAME = os.environ['STACK_NAME']
REGION = os.getenv('AWS_DEFAULT_REGION', 'us-west-2')
API_ENDPOINT = os.getenv('API_ENDPOINT', None)

def rest_url(api_name, ep_name='discover', stage='Prod', region=REGION):
    return f'https://{api_name}.execute-api.{region}.amazonaws.com/{stage}/${ep_name}/'


if __name__ == "__main__":
    # Given only our stack name and consistent names for local (to each stack) resources, find out
    # the API endpoint
    stack = aws_helper.CloudFormationStack(STACK_NAME)
    if not API_ENDPOINT:
        # Given only our stack name, find the RestApi end point
        cfn_rest_api = stack.get_output('DiscoverSchemaApi')
        cfn_lambda = stack.get_output('DiscoverSchemaLambda')
        cfn_role = stack.get_output('KinesisServiceRoleARN')
        api_stage = 'Prod'
        API_ENDPOINT = cfn_rest_api  #if cfn_rest_api else

    # The next two lines are the only ones you should need
    params = {'bucket': 'xcfield', 'key': 'instantdatamart/tests/readings_200lines.csv', 'format': 'schema'}
    r = requests.get(url=API_ENDPOINT, params=params)
    print(json.dumps(r.json()))
