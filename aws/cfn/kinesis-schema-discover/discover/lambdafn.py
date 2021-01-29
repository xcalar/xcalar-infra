import os
import sys
import json
import boto3
try:
    from .discover_schema import DiscoverSchema
except ImportError as e:
    from discover_schema import DiscoverSchema

KINESIS_ROLE_ARN = os.environ['KINESIS_ROLE_ARN']
STACK_NAME = os.environ['STACK_NAME']
KINESIS_CLIENT = boto3.client('kinesisanalyticsv2')

ds = DiscoverSchema(KINESIS_ROLE_ARN, KINESIS_CLIENT)

def printerr(s):
    print(s, file=sys.stderr)

def lambda_handler(event, context):
    data = None
    if isinstance(event, type({})):
        if 'queryStringParameters' in event:
            data = event['queryStringParameters']
        elif 'bucket' in event:
            data = event
        elif 'body' in event:
            data = event['body']
        elif 'message' in event:
            if 'body' in event['message']:
                data = event['message']['body']
            else:
                data = event['message']
    if not data:
        return {'statusCode': 400, 'body': json.dumps({ "message": "No valid data provided"})}
    #printerr(json.dumps(data))
    bucket = data['bucket']
    key = data['key']
    fmt = data['format'] if 'format' in data else 'schema'

    result = ds.discover(bucket, key)
    if fmt == 'schema':
        output = result.schema
    elif fmt == 'parsed':
        output = result.data
    elif fmt == 'full':
        output = {'InputSchema': result.schema, 'ParsedInputRecords': result.data}
    else:
        return {'statusCode': 400, 'body': json.dumps({"message": f"Invalid format={fmt} specified"})}
    return { 'statusCode': 200, 'body': json.dumps(output) }
