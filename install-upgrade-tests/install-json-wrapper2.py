#!/usr/bin/env python3.6

import json
import os
import argparse

preConfig = True
nfsServer = ""
nfsMountPoint = ""
nfsUsername = ""
nfsGroupname = ""
nfsOption = {}
ldapOption = ""
ldapDomainName = ""
ldapPassword = ""
ldapCompanyName = ""
ldapURI = ""
ldapUserDN = ""
ldapSearchFilter = ""
ldapKeyFile = ""
ldapActiveDir = ""
ldapUseTLS = ""
ldap = {}
installDir = ""
serDesDir = ""
hostnames = []
privHostnames = []
username = ""
port = "22"
credentials = {}

parser = argparse.ArgumentParser()

parser.add_argument("-n", "--hostnames", help="comma-separated list of cluster external/public host names")
parser.add_argument("-p", "--privHostnames", help="comma-separated list of cluster internal/public host names")
parser.add_argument("-u", "--username", help="name of the user that will run the installer")
parser.add_argument("-o", "--port", help="protocol port used to connect with cluster hosts")
parser.add_argument("-f", "--sshkeyfile", help="name of file holding key used for password-less access")
parser.add_argument("-s", "--password", help="ssh password for cluster access")
parser.add_argument("-t", "--userSettings", action='store_true', help="employ user ssh keys and config")
parser.add_argument("--preConfig", action='store_true', help="run pre-config.sh")
parser.add_argument("--nfsOption", choices=['INT', 'EXT', 'REUSE'], help="nfs type: xcalarNfs (INT), customerNfs (EXT), readyNfs (REUSE)")
parser.add_argument("--nfsServer", help="external nfs server address")
parser.add_argument("--nfsMntPt", help="external nfs server directory")
parser.add_argument("--nfsUsername", help="external nfs server username")
parser.add_argument("--nfsGroupname", help="external nfs server group name")
parser.add_argument("--nfsReuse", help="path of existing mount point")
parser.add_argument("--ldapInstall", choices=['true', 'false'], help="internal ldap: true, external ldap: false")
parser.add_argument("--ldapPassword", help="LDAP password")
parser.add_argument("--ldapDomain", help="LDAP domain name")
parser.add_argument("--ldapCompanyName", help="Certificate Authority company name")
parser.add_argument("--ldapURI", help="ldap URI")
parser.add_argument("--ldapUserDN", help="ldap user distinguished name")
parser.add_argument("--ldapSearchFilter", help="ldap search filter")
parser.add_argument("--ldapKeyFile", help="ldap TLS trusted key file")
parser.add_argument("--ldapActiveDir", help="Active Directory server: true, OpenLDAP server: false")
parser.add_argument("--ldapUseTLS", help="use TLS: true, don't use TLS: false")
parser.add_argument("--outputFile", help="name of JSON file to hold the formatted data")
parser.add_argument("--installDir", help="installation directory")
parser.add_argument("--serDesDir", help="serialization/deserialization directory")

args = parser.parse_args()

if args.hostnames:
    hostnames = args.hostnames.split(',')

if args.privHostnames:
    privHostnames = args.privHostnames.split(',')

if args.username:
    username = args.username

if args.port:
    port = args.port

if args.preConfig:
    preConfig=False

if args.sshkeyfile:
    sshkeyFile = open(args.sshkeyfile, "r")
    sshkey = sshkeyFile.read()
    sshkeyFile.close()
    credentials = { "sshKey": sshkey }

if args.password:
    credentials = { "password": args.password }

if args.userSettings:
    credentials = { "sshUserSettings": True }

if args.installDir:
    installDir = args.installDir

if args.serDesDir:
    serDesDir = args.serDesDir

if args.nfsServer:
    nfsServer = args.nfsServer

if args.nfsMntPt:
    nfsMountPoint = args.nfsMntPt

if args.nfsUsername:
    nfsUsername = args.nfsUsername

if args.nfsGroupname:
    nfsGroupname = args.nfsGroupname

if args.nfsServer:
    nfsServer = args.nfsServer

if args.nfsOption:
    if args.nfsOption == 'INT':
        nfsOption = {
            "option": "xcalarNfs"
        }
    elif args.nfsOption == 'EXT':
        nfsOption = {
            "option": "customerNfs",
            "nfsServer": nfsServer,
            "nfsMountPoint": nfsMountPoint,
            "nfsUsername": nfsUsername,
            "nfsGroup": nfsGroupname
        }
    elif args.nfsOption == 'REUSE':
        nfsOption = {
            "option": "readyNfs",
            "nfsMountPoint": nfsMountPoint
        }

if args.ldapPassword:
    ldapPassword = args.ldapPassword

if args.ldapDomain:
    ldapDomainName = args.ldapDomain

if args.ldapCompanyName:
    ldapCompanyName = args.ldapCompanyName

if args.ldapURI:
    ldapURI = args.ldapURI

if args.ldapUserDN:
    ldapUserDN = args.ldapUserDN

if args.ldapSearchFilter:
    ldapSearchFilter = args.ldapSearchFilter

if args.ldapKeyFile:
    ldapKeyFile = args.ldapKeyFile

if args.ldapActiveDir:
    if args.ldapActiveDir == 'true':
        ldapActiveDir = True
    elif args.ldapActiveDir == 'false':
        ldapActiveDir = False

if args.ldapUseTLS:
    if args.ldapUseTLS == 'true':
        ldapUseTLS = True
    elif args.ldapUseTLS == 'false':
        ldapUseTLS = False

if args.ldapInstall:
    if args.ldapInstall == 'true':
        ldap = {
            "xcalarInstall": True,
            "domainName": ldapDomainName,
            "companyName": ldapCompanyName,
            "password": ldapPassword,
            "ldapConfigEnabled": True
        }
    elif args.ldapInstall == 'false':
        ldap = {
            "ldap_uri": ldapURI,
            "userDN": ldapUserDN,
            "searchFilter": ldapSearchFilter,
            "serverKeyFile": ldapKeyFile,
            "activeDir": ldapActiveDir,
            "useTLS": ldapUseTLS,
            "ldapConfigEnabled": True
        }

print (json.dumps({
    "preConfig": preConfig,
    "nfsOption": nfsOption,
    "hostnames": hostnames,
    "privHostNames": privHostnames,
    "username": username,
    "port": port,
    "credentials": credentials,
    "installationDirectory": installDir,
    "serializationDirectory": serDesDir,
    "ldap": ldap
}))
