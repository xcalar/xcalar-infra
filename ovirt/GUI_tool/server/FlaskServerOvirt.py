# start server:
# FLASK_APP=VmShopUtils.py flask run --host=0.0.0.0
# then follow the directions on the console output...

import requests
import json
import getpass
import socket
import os
import sys
from flask import Flask
from flask import request
from flask import jsonify
from flask import Response
from natsort import natsorted, ns
import re
import OvirtServerLibs

# add ovirt/modules to path so can import shared Ovirt library
SCRIPT_DIR = os.path.dirname(os.path.abspath('__file__'))
sys.path.insert(1, os.path.join(SCRIPT_DIR, '../../'))
import modules.OvirtUtils

app = Flask(__name__)

JENKINS_URL=os.getenv('JENKINS_URL','https://jenkins.int.xcalar.com')
HOSTNAME=socket.gethostname()

STATUS_OK = 200
STATUS_NOT_FOUND = 404
STATUS_AUTH_ERR = 401
STATUS_ERR = 500

# common keys in API returns
ERROR = "error" # main resp JSON key to return in case of server errors only
RESULT = "result" # main resp JSON key to return non-error data to caller

'''
usage:

 raise InvalidCredentialsError(<error message>, status_code=<status code>)

@returns:
 {'error': <error message>,
  'status_code': 500 || <status code>
 }
'''
class InvalidCredentialsError(Exception):
    status_code = STATUS_AUTH_ERR

    def __init__(self, message, status_code=None, payload=None):
        Exception.__init__(self)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        self.payload = payload

    def to_dict(self):
        rv = dict(self.payload or ())
        rv[ERROR] = self.message
        return rv
    pass

'''
usage:

 raise MissingRequiredParamsException(<error message>, status_code=<status code>)

@returns:
 {'error': <error message>,
  'status_code': 500 || <status code>
 }
'''
class MissingRequiredParamsException(Exception):
    status_code = STATUS_ERR

    def __init__(self, message, status_code=None, payload=None):
        Exception.__init__(self)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        self.payload = payload

    def to_dict(self):
        rv = dict(self.payload or ())
        rv[ERROR] = self.message
        return rv
    pass

@app.errorhandler(InvalidCredentialsError)
@app.errorhandler(MissingRequiredParamsException)
def handle_invalid_usage(error):
    response = jsonify(error.to_dict())
    response.status_code = error.status_code
    return response

'''
@level arg: optional int
    0: stdout
    1: stderr (default)
'''
def print_wrap(msg, level=1):
    if level == 0:
        print(msg)
        sys.stdout.flush() # flushes so output will show in journalctl logs
    elif level == 1:
        print(msg, file=sys.stderr)
        sys.stderr.flush() # flushes so output will show in journalctl logs

@app.route("/", methods = ['GET', 'POST'])
def hello():
    print_wrap(request.args)
    return "Hello World!"

'''
    Returns list of RC builds in human sorted order.
    Each element in list is a hash as follows:
{
 'name': 'RC-xxxx,
 'flavors': {'prod':<path to prod build>, 'debug':<path to debug build>, etc.},
}

@optional param: 'regex': if supplied, will filter the list given the regex on the build names
i.e., '.*1\.4.*'
'''
@app.route("/get-rc-list", methods = ['POST'])
def getRCList():
    # rcMap will just be a hash, with a key for each bld, and value is the flavor hash
    # (TODO: Automate getting list of RC files.  For now relying on a JSON file in server dir)
    rcMap = OvirtServerLibs.read_json_file("RCs.json")

    myRegex = None
    api_params = extract_request_params(request, optional=['regex']) # doesnt throw exceptions when optional params only
    if api_params['regex']:
        myRegex = re.compile(api_params["regex"])

    # sort the keys in human order
    rcKeys = rcMap.keys()
    humanSortedRcKeys = natsorted(rcKeys, reverse=True)

    # form the individual hashes
    sortedRcList = []
    for sortedKey in humanSortedRcKeys:
        # if a regex was given, only include if it matches that
        includeKey = True
        if myRegex:
            if not myRegex.match(sortedKey):
                print_wrap("RC builds! " + sortedKey + " doesn't match the regex supplied to API")
                includeKey = False
        if includeKey:
            buildFlavors = rcMap[sortedKey]
            rcHash = {'name': sortedKey, 'flavors': buildFlavors}
            sortedRcList.append(rcHash)
    res = {"rclist": sortedRcList}
    resp = jsonify(res)
    resp.status_code = STATUS_OK
    return resp

'''
Checks if an URL looks like a valid RPM installer URL which can
be curled by the server.

params for this API:
    'url' (required): URL you'd like to validate

Returns (success case):
{'result': <result>}

where <result> = True if URL passes validation
and if not, an error string explaining the nature of the error
(@TODO: numbered results?)

@throws: MissingRequiredParamException
'''
@app.route("/validate/url", methods = ['POST'])
def check_url():
    api_params = extract_request_params(request, required=['url'])
    url = api_params['url']

    responseJson = {RESULT: None}
    # validate_installer_url throws ValueError if url validation
    # fails, else returns True
    try:
        modules.OvirtUtils.validate_installer_url(url)
        responseJson[RESULT] = True
    except ValueError as e:
        # throws ValueError if URL invalid, but still valid server response
        responseJson[RESULT] = str(e)
    resp = jsonify(responseJson)
    resp.status_code = STATUS_OK
    return resp

'''
Checks if a prospective hostname for a VM is valid.

params for this API:
    'hostname' (required): prospective hostname for a VM, to validate

Returns (success case):
{'status': <status>}
  where <status> = True if hosetanme is valid,
  and if invalid, an error String explaining the reason

@throws: MissingRequiredParamException
'''
@app.route("/validate/hostname", methods = ['POST'])
def check_hostname():
    api_params = extract_request_params(request, required=['hostname'])
    hostname = api_params['hostname']
    print_wrap("hostname to validate: {}".format(hostname))

    responseJson = {RESULT: None}
    try:
        modules.OvirtUtils.validate_hostname(hostname)
        responseJson[RESULT] = True
    except ValueError as e:
        # throws ValueError if hostname invalid, but this is still valid server response
        responseJson[RESULT] = str(e)
    resp = jsonify(responseJson)
    resp.status_code = STATUS_OK
    return resp

'''
Checks if can login to Jenkins with a set of credentials.

required API params:
    'user': Jenkins username
    'password': Jenkins password

401 status_code returned if unable to log in
'''
@app.route("/login", methods = ['POST'])
def tryLogin():
    jenkins_user = None
    jenkins_pass = None
    api_params = extract_request_params(request, required=['user', 'password'])
    ## DO NOT PRINT 'request' data!!  User's password is in here in plaintext
    jenkins_user = api_params['user']
    jenkins_pass = api_params['password']
    authenticated = login(jenkins_user, jenkins_pass)
    resp = jsonify("Welcome to Jenkins :)")
    resp.status_code = STATUS_OK
    return resp

'''
Trigger a paramaterized job in Jenkins.
    JSON params -
    Required:
    'user': Jenkins username
    'password': Jenkins password
    Optional:
    'job-params': dict of params to send to Jenkins job,
        where keys are names of Jenkins job's build params, and value is value to supply in job
        if None will trigger with job defaults
can call as:
/trigger/myjob?job-params={'param1':'val1'} for the params you want to pass to the jenkins job
'''
@app.route("/trigger/<job>", methods = ['POST'])
def triggerParameterizedJob(job):
    mainJobUrl = "{}/job/{}".format(JENKINS_URL, job)
    buildUrl = "{}/job/{}/buildWithParameters".format(JENKINS_URL, job)

    jenkins_user = None
    jenkins_pass = None
    jenkins_params = {}
    api_params = extract_request_params(request, required=['user', 'password'], optional=['job-params'])
    jenkins_user = api_params['user']
    jenkins_pass = api_params['password']
    if 'job-params' in api_params:
        jenkins_params = api_params['job-params']
    ## DO NOT PRINT 'request' data!!  User's password is in here in plaintext

    # can send params to Jenkins job either with query string on the URL (use requests' 'data' arg)
    # or as post data; going to send password as param so dont use URL string for now
    response = requests.post(buildUrl, auth=(jenkins_user, jenkins_pass), verify=False, data=jenkins_params)
    dumpResponse(response)
    resp = jsonify("Cool")
    resp.status_code = STATUS_OK
    return resp

'''
returns data payload sent to api, as json object

:request: flask.Request object (Accessible to all Flask endpoints)
'''
def get_request_json(request):
    requestDataAsStr = request.data.decode("utf-8", "strict")
    requestJson = json.loads(requestDataAsStr)
    return requestJson

'''
takes a request obj, and list of optional and required params and
returns hash with the values
if any required param not present, throws MissingRequiredParamsException

:request: flask.Request object ** (Each Flask endpoint has access to global' request' variable
    http://flask.pocoo.org/docs/1.0/api/#flask.Request
:required: list of required params to extract (throws MissingRequiredParmsException if any can't be extracted)
:optional: list of optional params to extract
:returns: hash, with key for each value in required and optional list

myParams = extract_request_params(requestObj, required=['foo', 'bar'], optional=['foobar'])
where myParams = {'foo': 'foosval', 'bar': 'barsval', 'foobar': None} (assuming 'foobar' wasn't passed)
'''
def extract_request_params(request, required=None, optional=None):
    # do NOT print 'request' data - user credentials could have been sent
    requestJson = get_request_json(request)
    params = {}
    if required:
        for param in required:
            if requestJson.get(param):
                params[param] = requestJson.get(param)
            else:
                raise MissingRequiredParamsException("param '{}' required to this api".format(param))
    if optional:
        for param in optional:
            params[param] = requestJson.get(param)
    return params

'''
Try logging in to Jenkins with a username/pass.
If it is invalid, raise InvalidCredentialsError
'''
def login(user, password):
    response = requests.get("{}/login".format(JENKINS_URL), auth=(user,password), verify=False)
    if response.status_code == STATUS_AUTH_ERR:
        raise InvalidCredentialsError("Invalid credentials logging in to Jenkins")
    return True

def dumpResponse(response):
    print_wrap("Response dump::")
    for attr, value in response.__dict__.items():
        print_wrap("=========\nResponse.{}:\n".format(attr), value)
