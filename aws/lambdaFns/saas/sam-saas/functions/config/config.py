import traceback
import os
from util.http_util import _make_reply

envNames = {"XCE_CLOUD_MODE": "",
            "XCE_CLOUD_SESSION_TABLE": None,
            "XCE_CLOUD_USER_POOL_ID": None,
            "XCE_CLOUD_CLIENT_ID": None,
            "XCE_SAAS_AUTH_LAMBDA_URL": None,
            "XCE_SAAS_MAIN_LAMBDA_URL": None,
            "XCE_CLOUD_REGION": "",
            "XCE_CLOUD_PREFIX": "xc",
            "XCE_CLOUD_HASH_KEY": "id"}


def printItem(item):
    if (item == "XCE_CLOUD_MODE"):
        return "{}=1\n".format(item)
    else:
        return "{}={}\n".format(item, os.getenv(item, default=envNames[item]))


configResult = "".join([printItem(item) for item in envNames.keys()])


def lambda_handler(event, context):
    try:
        path = event['path']

        if path == '/config':
            reply = _make_reply(200, {
                'config': configResult
            })
        else:
            reply = _make_reply(400, "Invalid endpoint: %s" % path)
    except Exception as e:
        traceback.print_exc()
        reply = _make_reply(400, "Exception has occurred: {}".format(e))
    return reply
