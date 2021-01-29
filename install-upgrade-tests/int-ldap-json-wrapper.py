#!/usr/bin/env python3.6

import json
import os
import argparse

domainName = ""
password = ""
companyName = ""

parser = argparse.ArgumentParser()

parser.add_argument("-p", "--password", help="LDAP password")
parser.add_argument("-d", "--domainName", help="LDAP domain name")
parser.add_argument("-c", "--companyName", help="Certificate Authority company name")

args = parser.parse_args()

if args.password:
    password = args.password

if args.domainName:
    domainName = args.domainName

if args.companyName:
    companyName = args.companyName

print(json.dumps({"domainName": domainName,
                  "password": password,
                  "companyName": companyName}))
