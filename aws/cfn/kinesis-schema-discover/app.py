#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
import logging

import boto3
from botocore.exceptions import ClientError

this_dir = os.path.dirname(os.path.abspath(__file__))
discover_dir = os.path.abspath(os.path.join(this_dir, 'discover'))
sys.path.insert(0, discover_dir)

import aws_helper
from discover_schema import DiscoverSchema, DiscoverSchemaResult


def bucket_and_key(uri):
    bnk = uri[5:].split('/')
    return (bnk[0], '/'.join(bnk[1:]))

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.stderr.write("Must specify s3url to analyze\n")
        sys.exit(2)

    stack = aws_helper.CloudFormationStack(os.getenv('STACK_NAME', 'DiscoverSchemaStack'))
    KINESIS_ROLE_ARN = stack.get_output('KinesisServiceRoleARN')
    os.putenv('KINESIS_ROLE_ARN',KINESIS_ROLE_ARN)
    os.environ['KINESIS_ROLE_ARN'] = KINESIS_ROLE_ARN
    s3 = boto3.client('s3')
    try:
        from lambdafn import lambda_handler
        kinesis = boto3.client('kinesisanalyticsv2')
        ds = DiscoverSchema(KINESIS_ROLE_ARN, kinesis)
        for arg in sys.argv[1:]:
            if arg.startswith('s3://'):
                s3arg = arg
                bucket, key = bucket_and_key(s3arg)
            else:
                if not os.path.exists(arg):
                    raise Exception(f"File {arg} not found")
                bucket = 'xcfield'
                key = 'tmp/{}'.format(os.path.basename(arg))
                with open(arg,'rb') as fp:
                    resp = s3.put_object(Bucket=bucket, Key=key, Body=fp.read())
                s3arg = f's3://{bucket}/{key}'
            event = { 'bucket': bucket, 'key': key }
            lambda_handler(event, {})
            discovered = ds.discover(bucket, key)
    except ClientError as e:
        logging.error(e)
        raise e
    except Exception as e:
        raise e
    output = {}
    output["Schema"] = discovered.schema
    numr = len(discovered.data)
    idx=0
    output["Data"] = []
    for idx in range(min(3,numr)):
        line_json = {}
        line_json[str(idx)] = line = discovered.data[idx]
        output["Data"].append(line_json)
    print(json.dumps(output))
