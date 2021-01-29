import json
import sqlite3

def convertToDict(rowHeaders, row):
    return { name: value for (name, value) in zip(rowHeaders, row) }

def listTable(c, tableName):
    c.execute("SELECT * FROM " + tableName)
    resultSet = c.fetchall()
    rowHeaders = [ tmp[0] for tmp in c.description ]
    return ([convertToDict(rowHeaders, row) for row in resultSet])

def listKeys(c, name, organization):
    if name is not None:
        c.execute('SELECT owner.name, license.license_key, license.deployment_type FROM license INNER JOIN owner ON license.org_id = owner.org_id WHERE owner.name = %(name)s', {"name":name})
    elif organization is not None:
        c.execute('SELECT organization.name, license.license_key, license.deployment_type FROM license INNER JOIN organization on license.org_id = organization.org_id WHERE organization.name = %(organization)s', {"organization": organization})
    return c.fetchall()
def getUnusedKey(c):
    c.execute('SELECT organization.name, license_key from license inner join organization on license.org_id = organization.org_id WHERE license_id NOT IN (SELECT DISTINCT license_id FROM activation)')
    return c.fetchall()
def insert(c, name, organization, key, deploymentType, salesforceId):
    if organization is None:
        raise ValueError("organization is required")

    if key is None:
        raise ValueError("key is required")

    # Retrieve organization id or create one if don't exist
    try:
        c.execute("SELECT organization.org_id FROM organization WHERE organization.name = %(organization)s", {"organization": organization})
        organizationId = c.fetchone()[0]
    except Exception as e:
        c.execute("INSERT INTO organization (name) VALUES (%(organization)s)", {"organization": organization})
        organizationId = c.lastrowid

    # Insert person into owner table if don't exist
    if name is not None:
        c.execute("SELECT name FROM owner WHERE name = %(name)s AND org_id = %(orgid)s", {"name": name, "orgid": organizationId })
        if (len(c.fetchall()) == 0):
            c.execute("INSERT INTO owner (name, org_id) VALUES (%(name)s, %(orgid)s)", {"name": name, "orgid": organizationId})

    # Insert key entry
    c.execute("INSERT INTO license (license_key, deployment_type, org_id) VALUES (%(key)s, %(deploymentType)s, %(orgid)s)", {"key": key, "deploymentType": deploymentType, "orgid": organizationId})

    if salesforceId is not None:
        c.execute("INSERT INTO salesforce (SF_account_id, org_id) VALUES (%(sfId)s, %(orgid)s)", { "sfId": salesforceId, "orgid": organizationId })


def deleteName(c, name):
    c.execute("DELETE FROM owner WHERE name=:name", {"name": name})

def deleteKey(c, key):
    c.execute("DELETE FROM license WHERE license_key=:key", {"key": key})

def deleteOrganization(c, organization):
    c.execute("DELETE FROM organization WHERE name=:organization", {"organization": organization})
