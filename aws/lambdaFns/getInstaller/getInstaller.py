import requests
import json
import boto3

try:
    s3
except:
    s3 = boto3.client("s3")

bucket = "xcrepo"
installerPaths = {
    "1.3.2": "builds/db56e5d8-e167bb6a/prod/xcalar-1.3.2-1758-installer",
    "1.3.0": "builds/cad778ee-cbb4f2f2/prod/xcalar-1.3.0-1548-installer",
    "1.2.3": "builds/3c9a47f4-65ad6827/prod/xcalar-1.2.3-1296-installer",
    "1.2.2": "builds/2f08e5a2-b820c309/prod/xcalar-1.2.2-1264-installer",
    "1.2.1": "builds/67cf7211-962b4eb4/prod/xcalar-1.2.1-1044-installer"
}
installerPaths["latest"] = installerPaths["1.3.2"]

def lambda_handler(event, context):
    licenseServer="https://x3xjvoyc6f.execute-api.us-west-2.amazonaws.com/production/license/api/v1.0/checkvalid"
    #licenseServer="https://zd.xcalar.net/license/api/v1.0/checkvalid"
    ret = {}
    ret["success"] = False

    try:
        licenseKey = event['licenseKey']
    except:
        ret["error"] = "Missing argument licenseKey"
        return ret

    try:
        numNodes = int(event['numNodes'])
    except:
        numNodes = 1

    try:
        installerVersion = event["installerVersion"]
    except:
        installerVersion = "latest"

    try:
        headers = { "Content-Type": "application/json" }
        data = { "key": licenseKey }
        jsonData = json.dumps(data)
        response = requests.post(licenseServer, data=jsonData, headers=headers)
    except:
        ret["error"] = "Unknown error while contacting licenseServer"
        return ret

    try:
        responseDict = json.loads(response.text)
    except:
        ret["error"] = "Could not parse response"
        return ret

    try:
        if not responseDict["success"]:
            ret["error"] = responseDict["error"]
            return ret

        keyInfo = responseDict["keyInfo"]
        numNodesLicensed = int(keyInfo["node_count"])
    except:
        ret["error"] = "Response is malformed"
        return ret

    try:
        installerPath = installerPaths[installerVersion]
    except:
        ret["error"] = "Version \"%s\" not found" % installerVersion
        return ret

    # numNodesLicensed == 0 is god-mode. Only Xcalar employees should have that
    if numNodesLicensed != 0 and numNodes > numNodesLicensed:
        ret["error"] = "Tried to deploy %d nodes when only %d are licensed" % (numNodes, numNodesLicensed)
        return ret

    params = { 'Bucket': bucket, 'Key': installerPath }
    signedUrl = s3.generate_presigned_url(ClientMethod="get_object", Params=params, ExpiresIn=1800)
    ret["signedUrl"] = signedUrl

    ret["success"] = True
    return ret

