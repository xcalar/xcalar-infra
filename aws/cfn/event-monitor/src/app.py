import os
import sys
import json
import boto3
from boto3.dynamodb.conditions import Attr, And
import uuid
from datetime import datetime

def lambda_handler(event, context):
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['TABLE_NAME'])
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({
                "msg" : f"Failed to connect to dynamodb, table {os.environ['TABLE_NAME']}",
                "error" : str(e)
            })}

    if event["httpMethod"] == "POST":
        event_id = event["requestContext"].get("requestId", uuid.uuid4())
        ts = event["requestContext"].get("requestTimeEpoch", int(datetime.now().timestamp()*1000))

        try:
            table.put_item(
            Item={
                    "id" : event_id,
                    "timestamp" : ts,
                    "event" : event["body"]
                })
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "msg" : "Event added",
                    "event": {"id" : event_id, "timestamp" : ts, "body" : event["body"]},
                })}
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "msg" : f"Failed to insert event into table {os.environ['TABLE_NAME']}",
                    "error" : str(e)
                })}
    elif event["httpMethod"] == "GET":
        query = event.get("queryStringParameters", None)
        if query == "None" or query is None:
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "msg" : "Empty query string, search aborted",
                    "event" : event
                })}

        try:
            # BOOOOM mindblown
            if len(query) == 1:
                FilterExpression = Attr(f'event.{list(query)[0]}').eq(list(query.values())[0])
            else:
                FilterExpression = And(*[(Attr(f'event.{key}').eq(value)) for key, value in query.items()])
            res = table.scan(FilterExpression=FilterExpression)
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "msg" : "Event found",
                    "events" : res['Items']
                })}
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "msg" : f"Failed to scan table {os.environ['TABLE_NAME']}",
                    "query" : query,
                    "error" : str(e)
                })}
    else:
        return {
            "statusCode": 500,
            "body": json.dumps({
                "msg" : "Method Unsupported. Use GET or POST",
            }),
        }
