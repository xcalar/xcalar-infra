#!/usr/bin/env python3.6

import json
import os
import argparse

ldapUri = ""
userDN = ""
searchFilter = ""
serverKeyFile = ""
activeDir = ""
useTLS = ""

parser = argparse.ArgumentParser()

parser.add_argument("-l", "--ldapUri", help="the URI of the external LDAP")
parser.add_argument("-u", "--userDN", help="the userDN for LDAP access")
parser.add_argument("-s", "--searchFilter", help="the LDAP search filter to be applied during login")
parser.add_argument("-k", "--serverKeyFile", help="the certificate chain for the LDAP server cert")
parser.add_argument("-a", "--activeDir", choices=["true", "false"], help="is the LDAP server an Active Directory instance")
parser.add_argument("-t", "--useTLS", choices=["true", "false"], help="should the client request TLS upon connection")

args = parser.parse_args()

if args.ldapUri:
    ldapUri = args.ldapUri

if args.userDN:
    userDN = args.userDN

if args.searchFilter:
    searchFilter = args.searchFilter

if args.serverKeyFile:
    serverKeyFile = args.serverKeyFile

if args.activeDir:
    activeDir = args.activeDir

if args.useTLS:
    useTLS = args.useTLS

print(json.dumps({"ldap_uri": ldapUri,
                  "userDN": userDN,
                  "searchFilter": searchFilter,
                  "serverKeyFile": serverKeyFile,
                  "activeDir": activeDir,
                  "useTLS": useTLS}))
