from datetime import datetime, timedelta
from collections import defaultdict
import subprocess
import ast
import re
import pymysql
import os
import sys
import json
import logging
import requests
import boto3
import zlib
from base64 import b64decode
from six import string_types

logger = logging.getLogger()
logger.setLevel(logging.INFO)

from flask import Flask, jsonify, abort, render_template, g, request, make_response, current_app
from functools import update_wrapper
import licenseServerApi

# Copied from http://flask.pocoo.org/snippets/56
# This creates a decoration @crossdomain that allows
# that endpoint to be called from another domain via AJAX
def crossdomain(origin=None, methods=None, headers=None,
                max_age=21600, attach_to_all=True,
                automatic_options=True):
    if methods is not None:
        methods = ', '.join(sorted(x.upper() for x in methods))

    if headers is not None and not isinstance(headers, string_types):
        headers = ', '.join(x.upper() for x in headers)

    if not isinstance(origin, string_types):
        origin = ', '.join(origin)

    if isinstance(max_age, timedelta):
        max_age = max_age.total_seconds()

    def get_methods():
        if methods is not None:
            return methods
        options_resp = current_app.make_default_options_response()
        return options_resp.headers['allow']

    def decorator(f):
        def wrapped_function(*args, **kwargs):
            if automatic_options and request.method == 'OPTIONS':
                resp = current_app.make_default_options_response()
            else:
                resp = make_response(f(*args, **kwargs))

            if not attach_to_all and request.method != 'OPTIONS':
                return resp

            h = resp.headers
            h['Access-Control-Allow-Origin'] = origin
            h['Access-Control-Allow-Methods'] = get_methods()
            h['Access-Control-Max-Age'] = str(max_age)

            if headers is not None:
                h['Access-Control-Allow-Headers'] = headers

            return resp

        f.provide_automatic_options = False
        f.required_methods = ['OPTIONS']
        return update_wrapper(wrapped_function, f)

    return decorator

app = Flask(__name__)

app.config.from_object('config')

#app.config.from_envvar('XC_LICENSE_SERVER_SETTINGS')

# licenseKeyDb = app.config["LICENSE_KEY_DB"]
# dbUpgrade = app.config["LICENSE_KEY_DB_UPGRADE"]
privKey = os.environ["LAMBDA_TASK_ROOT"] + app.config["XCALAR_PRIVATE_KEY"]
pubKey = os.environ["LAMBDA_TASK_ROOT"] + app.config["XCALAR_PUBLIC_KEY"]

createKeyCmd = os.environ["LAMBDA_TASK_ROOT"] + "/CreateKey.py"
readKeyCmd = os.environ["LAMBDA_TASK_ROOT"] + "/readKey"

rds_host = app.config["RDS_HOST"]
name = app.config["NAME"]
password = app.config["PASSWORD"]
db_name = app.config["DB_NAME"]
# Database management
def getDb():
    """Opens a new database connection if there is none yet for the
    current application context.
    """
    if not hasattr(g, 'rds_db'):
        try:
            g.rds_db = pymysql.connect(rds_host, user=name, passwd=password, db=db_name, connect_timeout=5)
            logger.info("Connecting to RDS...")
        except:
            logger.error("ERROR: Unexpected error: Could not connect to MySql instance.")
            sys.exit()

    logger.info("SUCCESS: Connection to RDS mysql instance succeeded")
    return g.rds_db

@app.teardown_appcontext
def closeDb(error):
    """Closes the database again at the end of the request."""
    if hasattr(g, 'rds_db'):
        g.rds_db.commit()
        logger.info("Closing RDS connection...")
        g.rds_db.close()

def auditTrail(userId, action, message):
    with getDb().cursor() as cursor:
        cursor.execute("INSERT INTO audit (`userId`, `action`, `message`) VALUES (%(userId)s, %(action)s, %(message)s)", {"userId": userId, "action": action, "message": message })

# def initDb():
#     db = getDb()
#     with app.open_resource(dbUpgrade, mode='r') as f:
#         db.cursor().executescript(f.read())
#     db.commit()

# @app.cli.command('initdb')
# def initDbCommand():
#     initDb()
#     print 'Database initialized.'

@app.route('/license/api/v1.0/keyinfo/<path:key>', methods=['GET'])
@crossdomain(origin="*")
def fetchInfo(key):
    keyInfo = getKeyInfo(key=key)
    with getDb().cursor() as cursor:
        cursor.execute("""
            SELECT name
            FROM organization INNER JOIN license ON organization.org_id = license.org_id
            WHERE license.license_key = %(licenseKey)s
            """, {"licenseKey": key})
        organization = cursor.fetchall()
        if (len(organization) > 0 and len(organization[0]) > 0):
            keyInfo['organization'] = organization[0][0]
    return jsonify(keyInfo)

def getKeyInfo(key):
    try:
        licenseText = zlib.decompress(b64decode(key), 16+zlib.MAX_WBITS)
        keyProps = { key:value for (key, value) in [ element.split("=") for element in licenseText.split("\n") if len(element.split("=")) > 1 ] }
        del keyProps["signature"]
        keyProps["key"] = key
        return keyProps
    except:
        pass

    p = subprocess.Popen([readKeyCmd, "-k", pubKey, "-l", key], stdout=subprocess.PIPE)
    cmdOutput = p.communicate()[0]
    if p.returncode != 0:
        raise Exception("%s returned %d" % (readKeyCmd, p.returncode))

    keyProps = {}
    for line in cmdOutput.splitlines():
        elements = json.loads("{%s}" % line)
        keyProps.update(elements)

    return keyProps

def getKeys(name = None, organization = None):
    with getDb().cursor() as cursor:
        keys = []
        keys = licenseServerApi.listKeys(cursor, name, organization)

    if not keys:
        return []
    return [addDeploymentInfo(getKeyInfo(k[1]), k[2]) for k in keys]

def addDeploymentInfo(keyInfo, deployementType):
    keyInfo.update({"deploymentType": deployementType})
    return keyInfo

# Request handlers
@app.errorhandler(404)
def pageNotFound(error):
    return render_template('_error_license.html'), 404

@app.route('/')
def index():
    return "Hello, World!"

# XXX Use JWT or some other way to secure these HTTP endpoints (beginning with secure/)
@app.route('/license/api/v1.0/secure/listactivation', methods=['POST'])
def listActivation():
    try:
        return listTable("activation", request.get_json())
    except:
        abort(500)

@app.route('/license/api/v1.0/secure/listowner', methods=['POST'])
def listOwner():
    try:
        return listTable("owner", request.get_json())
    except:
        abort(500)

@app.route('/license/api/v1.0/secure/listlicense', methods=['POST'])
def listLicense():
    try:
        return listTable("license", request.get_json())
    except:
        abort(500)

@app.route('/license/api/v1.0/secure/listorganization', methods=['POST'])
def listOrganization():
    try:
        return listTable("organization", request.get_json())
    except:
        abort(500)

@app.route('/license/api/v1.0/secure/listmarketplace', methods=['POST'])
def listMarketplace():
    try:
        return listTable("marketplace", request.get_json())
    except:
        abort(500)

@app.route('/license/api/v1.0/secure/genlicense', methods=['POST'])
@crossdomain(origin="*", headers="Content-Type, Origin")
def createLicense():
    userId = "nobody"
    jsonInput = request.get_json();
    if "secret" not in jsonInput or jsonInput["secret"] != "xcalarS3cret":
        abort(403)
    del jsonInput["secret"]

    if "userId" not in jsonInput:
        abort(403)

    userId = jsonInput["userId"]
    del jsonInput["userId"]

    auditTrail(userId, "createLicense", json.dumps(jsonInput))

    if "product" not in jsonInput:
        abort(400)
    product = jsonInput["product"]

    if "family" not in jsonInput:
        if product == "Xcalar Design CE" or product == "Xcalar Design EE":
            family = "Xcalar Design"
        else:
            family = "Xcalar Data Platform"
        jsonInput["family"] = family

    args = ["python", createKeyCmd]

    if jsonInput["licenseType"] == "Production":
        encrypted_key = os.environ["private_key_prod_0"]
    else:
        encrypted_key = os.environ["private_key_dev"]
    del jsonInput["licenseType"]

    decrypted_key = boto3.client('kms').decrypt(CiphertextBlob=b64decode(encrypted_key))['Plaintext']
    os.environ["pKey"] = decrypted_key
    args.extend(["--kv", "pKey"])

    compress = False
    for k, v in jsonInput.items():
        hypen = '--' if len(k) > 1 else '-'
        if k == "compress":
            if str(v).lower() == "true":
                args.append("-z")
                compress = True
        elif k == "jdbc":
            if str(v).lower() == "true":
                args.append("--jdbc")
        elif str(v).strip():
            args.extend([hypen + k, str(v)])

    pr = subprocess.Popen(args,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE)

    out, err = pr.communicate()

    if pr.returncode != 0:
        raise ValueError(err)

    result = {}

    if compress:
        result["Compressed_Sig"] = out.strip().decode('utf-8')
    else:
        for line in out.strip().decode('utf-8').splitlines():
            k, v = line.split('=', 1)
            result[k] = v

    return jsonify(**result)

@app.route('/license/api/v1.0/secure/addlicense', methods=['POST'])
@crossdomain(origin="*", headers="Content-Type, Origin")
def insertLicense():
    jsonInput = request.get_json();
    userId = "nobody"
    if "secret" not in jsonInput or jsonInput["secret"] != "xcalarS3cret":
        abort(403)


    if "userId" not in jsonInput:
        abort(403)

    userId = jsonInput["userId"]

    auditTrail(userId, "issueLicense", json.dumps(jsonInput))


    name = jsonInput.get("name", None)

    try:
        organization = jsonInput["organization"]
        key = jsonInput["key"]
        deploymentType = jsonInput["deploymentType"]
        salesforceId = jsonInput.get("salesforceId", None)
    except:
        abort(404)

    try:
        with getDb().cursor() as cursor:
            licenseServerApi.insert(cursor, name, organization, key, deploymentType, salesforceId)
    except:
        abort(404)

    return jsonify({"success": True})

def listTable(tableName, jsonInput):
    if "secret" not in jsonInput or jsonInput["secret"] != "xcalarS3cret":
        raise Exception("Invalid secret provided")

    if not tableName.isalnum():
        raise Exception("tableName must contain only alpha-numeric characters")

    with getDb().cursor() as cursor:
        return jsonify(licenseServerApi.listTable(cursor, tableName))


@app.route('/license/api/v1.0/keys/<string:ownerName>', methods=['GET'])
@crossdomain(origin="*")
def getKeysByOwner(ownerName):
    keys = getKeys(name=ownerName)
    if not keys:
        return jsonify({})

    return jsonify({'key': keys})

@app.route('/license/api/v1.0/keysbyorg/<string:organizationName>', methods=['GET'])
@crossdomain(origin="*")
def getKeysByOrg(organizationName):
    keys = getKeys(organization=organizationName)
    if not keys:
        return jsonify({})

    return jsonify({'key': keys})

@app.route('/license/api/v1.0/checkvalid', methods=['POST'])
def checkvalid():
    jsonInput = request.get_json()
    if "key" not in jsonInput:
        abort(400)
    key = jsonInput["key"]

    with getDb().cursor() as cursor:
        retObj = {"success": False}

        cursor.execute("""
            INSERT INTO activation (license_id, active)
            SELECT license_id, active
            FROM license
            WHERE license.license_key = %(key)s;
            """,
            {"key": key})
        if not cursor.rowcount:
            retObj["error"] = "License key not found"
        else:
            activeRowId = cursor.lastrowid

            cursor.execute("""
                SELECT active
                FROM activation
                WHERE act_id = %(rowid)s""",
                {"rowid": activeRowId})
            dbActive = cursor.fetchone()
            if dbActive[0]:
                try:
                    retObj["keyInfo"] = getKeyInfo(key)
                    retObj["success"] = True
                except Exception as e:
                    retObj["error"] = "Error parsing license key: %s" % e
            else:
                retObj["error"] = "License key inactive"

    return jsonify(retObj)

@app.route('/license/api/v1.0/marketplacedeploy', methods=['POST'])
def marketplaceDeploy():
    jsonInput = request.get_json()
    try:
        marketplaceName = jsonInput["marketplaceName"]
        url = jsonInput["url"]
        key = jsonInput["key"]
    except:
        abort(400)

    with getDb().cursor() as cursor:
        retObj = {"success": False}

        cursor.execute("SELECT license_key FROM license WHERE license_key = %(licenseKey)s", { "licenseKey": key })
        if not cursor.rowcount:
            retObj["error"] = "License key not found"
            return jsonify(retObj)

        cursor.execute("INSERT INTO marketplace (license_id, url, marketplaceName) SELECT license_id, %(url)s, %(marketplaceName)s FROM license WHERE license_key = %(licenseKey)s", {"licenseKey": key, "url": url, "marketplaceName": marketplaceName })
        retObj["success"] = True

    return jsonify(retObj)

@app.route('/license/api/v1.0/getdeployment/<string:organizationName>', methods=['GET'])
@crossdomain(origin="*")
def getDeployments(organizationName):
    with getDb().cursor() as cursor:
        cursor.execute("SELECT url, marketplaceName, timestamp, sas_uri, license.license_key FROM marketplace INNER JOIN license ON marketplace.license_id = license.license_id INNER JOIN organization ON license.org_id = organization.org_id WHERE organization.name = %(orgName)s ORDER BY marketplace.timestamp DESC", { "orgName": organizationName })
        headers = [ "url", "marketplaceName", "timestamp", "sas_uri", "licenseKey" ]
        retVals = []
        for row in cursor.fetchall():
            dictionary = { name: value for (name, value) in zip(headers, row) }
            dictionary["keyInfo"] = getKeyInfo(dictionary["licenseKey"])
            del dictionary["licenseKey"]
            retVals.append(dictionary)
        return jsonify(retVals)

@app.route('/license/api/v1.0/activations/<path:key>', methods=['GET'])
def activations(key):
    with getDb().cursor() as cursor:
        actives = []
        cursor.execute("""
            SELECT timestamp, license.license_key
            FROM activation INNER JOIN license ON activation.license_id = license.license_id
            """)
        actives = cursor.fetchall()
        return jsonify({"activations": actives})

@app.route('/license/api/v1.0/keyshtml/<string:ownerName>', methods=['GET'])
def getHtmlKeysByOwner(ownerName):
    keys = getKeys(name=ownerName)
    if not keys:
        abort(404)

    output = sorted(keys, key=lambda k: datetime.strptime(k['expiration'], '%m/%d/%Y'), reverse=True)
    return render_template('_table_render.html', keys=output)

@app.route('/license/api/v1.0/keysbyorghtml/<string:organizationName>', methods=['GET'])
def getHtmlKeysByOrg(organizationName):
    keys = getKeys(organization=organizationName)
    if not keys:
        abort(404)

    output = sorted(keys, key=lambda k: datetime.strptime(k['expiration'], '%m/%d/%Y'), reverse=True)
    return render_template('_table_render.html', keys=output)

@app.route('/license/api/v1.0/unusedkey', methods=['GET'])
def getUnusedKey():
    try:
        keys = []
        with getDb().cursor() as cursor:
            keys = licenseServerApi.getUnusedKey(cursor, name, organization, key)
    except:
        abort(404)
    return jsonify(keys)

if __name__ == '__main__':
    app.run(debug=False,host='0.0.0.0')
