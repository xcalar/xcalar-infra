#!/usr/bin/env python3.6

import json
import os
import argparse

nfsServer = ""
nfsMountPoint = ""
nfsUsername = ""
nfsGroupname = ""
nfsOptions = {}
hostnames = []
privHostnames = []
username = ""
port = "22"
credentials = {}
installDir = ""

parser = argparse.ArgumentParser()

parser.add_argument("-n", "--hostnames", help="comma-separated list of cluster external/public host names")
parser.add_argument("-p", "--privHostnames", help="comma-separated list of cluster internal/public host names")
parser.add_argument("-u", "--username", help="name of the user that will run the installer")
parser.add_argument("-o", "--port", help="protocol port used to connect with cluster hosts")
parser.add_argument("-f", "--sshkeyfile", help="name of file holding key used for password-less access")
parser.add_argument("-s", "--password", help="ssh password for cluster access")
parser.add_argument("--nfsServer", help="external nfs server address")
parser.add_argument("--nfsMntPt", help="external nfs server directory")
parser.add_argument("--nfsUsername", help="external nfs server username")
parser.add_argument("--nfsGroupname", help="external nfs server group name")
parser.add_argument("--inputFile", help="name of file with cluster config data")
parser.add_argument("--outputFile", help="name of JSON file to hold the formatted data")
parser.add_argument("--installDir", help="installation directory")
parser.add_argument("--nfsReuse", help="path of existing nfs mount")

args = parser.parse_args()

if args.hostnames:
    hostnames = args.hostnames.split(',')

if args.privHostnames:
    privHostnames = args.privHostnames.split(',')

if args.username:
    username = args.username

if args.port:
    port = args.port

if args.sshkeyfile:
    sshkeyFile = open(args.sshkeyfile, "r")
    sshkey = sshkeyFile.read()
    sshkeyFile.close()
    credentials = { "sshKey": sshkey }

if args.password:
    credentials = { "password": args.password }

if args.nfsServer:
    nfsServer = args.nfsServer

if args.nfsMntPt:
    nfsMountpoint = args.nfsMntPt

if args.nfsUsername:
    nfsUsername = args.nfsUsername

if args.nfsGroupname:
    nfsGroupname = args.nfsGroupname

if args.nfsServer:
    nfsOptions = {"nfsServer": nfsServer, "nfsMountPoint": nfsMountpoint,
                  "nfsUsername": nfsUsername, "nfsGroup": nfsGroupname}
if args.nfsReuse:
     nfsOptions["nfsReuse"] = args.nfsReuse

outputObj = {"nfsOption": nfsOptions,
             "hostnames": hostnames,
             "privHostNames": privHostnames,
             "username": username,
             "port": port,
             "credentials": credentials}

if args.installDir:
    outputObj["installationDirectory"] = args.installDir

print (json.dumps(outputObj))

