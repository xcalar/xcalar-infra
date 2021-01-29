import json
def _make_reply(code, message, origin='*'):
    return {
        'statusCode': code,
        'body': json.dumps(message),
        'headers': {
            'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Credentials': 'true'
        }}

def _make_options_reply(code, origin):
    return {
        'statusCode': code,
        'headers': {
             'Content-Type': 'application/json',
             'Access-Control-Allow-Origin': origin,
             'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token',
             'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
             'Access-Control-Allow-Credentials': 'true'
        }}

def _replace_headers_origin(reply, headers_origin):
    reply['headers']['Access-Control-Allow-Origin'] = headers_origin
    return reply

def _http_status(resp):
    return resp['ResponseMetadata']['HTTPStatusCode']
