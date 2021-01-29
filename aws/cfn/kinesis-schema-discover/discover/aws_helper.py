import os
import logging

import boto3
from botocore.exceptions import ClientError


class CloudFormationStack():
    def __init__(self, stack_name=None):
        self.stack_name = stack_name if stack_name else os.environ['STACK_NAME']
        self.client = boto3.client('cloudformation')
        self.stack = self.client.describe_stacks(StackName=self.stack_name)['Stacks'][0]
        self.outputs = {}
        for output in self.stack['Outputs']:
            self.outputs[output['OutputKey']] = output['OutputValue']

    def get_stack_resource(self, logical_id):
        res = self.client.describe_stack_resource(StackName=self.stack_name,
                                                  LogicalResourceId=logical_id)['StackResourceDetail']
        return res

    def get_output(self, logical_id):
        return self.outputs[logical_id]

class S3Obj:
    def __init__(self, bucket, key):
        self.bucket = bucket
        self.key = key

    def put_object(self, source, s3client):
        with open(source, 'rb') as fp:
            resp = s3client.put_object(Bucket=self.bucket, Key=self.key, Body=fp.read())
            return resp

    def get_object(self, dest, s3client):
        with open(dest, 'wb') as fp:
            try:
                resp = s3client.get_object(Bucket=self.bucket, Key=self.key)
                fp.write(resp['Body'].read())
                return resp
            except ClientError as e:
                logging.error(e)
                return None



