#!/usr/bin/env python3
import boto3
import time
from botocore.exceptions import ClientError
from schema_checksum import SchemaChecksum


class DiscoverSchemaResult():
    def __init__(self, bucket, key, data, elapsed_time):
        self.bucket = bucket
        self.key = key
        self.data = data['ParsedInputRecords']
        data['InputSchema']['elapsedTime'] = elapsed_time
        checksum = SchemaChecksum()
        strict_order = data['InputSchema']['RecordFormat']['RecordFormatType'] != "JSON"
        data['InputSchema']['checksum'] = \
            checksum.compute_checksum(data['InputSchema']['RecordColumns'], strict_order)
        self.schema = data['InputSchema']

class DiscoverSchema():
    def __init__(self, role_arn, client=None):
        self.role_arn = role_arn
        self.client = client if client else boto3.client('kinesisanalyticsv2')

    def discover(self, bucket, key):
        start_time = time.time()
        discovered = self.client.discover_input_schema(ServiceExecutionRole=self.role_arn,
                                                       S3Configuration={
                                                           'BucketARN': f'arn:aws:s3:::{bucket}',
                                                           'FileKey': key
                                                       })
        elapsed_time = time.time() - start_time
        return DiscoverSchemaResult(bucket, key, discovered, elapsed_time)
