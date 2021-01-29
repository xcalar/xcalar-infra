#!/usr/bin/env python3.6

import argparse
from urllib.parse import urlencode
from collections import defaultdict

hostnames = []
username = ""
port = "22"
credentials = {}
urldict=defaultdict(list)

parser = argparse.ArgumentParser()

parser.add_argument("-n", "--hostnames", help="comma-separated list of cluster external/public host names")
parser.add_argument("-u", "--username", help="name of the user that will run the installer")
parser.add_argument("-o", "--port", help="protocol port used to connect with cluster hosts")
parser.add_argument("-f", "--sshkeyfile", help="name of file holding key used for password-less access")
parser.add_argument("-s", "--password", help="ssh password for cluster access")

args = parser.parse_args()

if args.hostnames:
    hostnames = args.hostnames.split(',')

if args.username:
    username = args.username

if args.port:
    port = args.port

if args.sshkeyfile:
    sshkeyFile = open(args.sshkeyfile, "r")
    sshkey = sshkeyFile.read().rstrip()
    sshkeyFile.close()
    credentials = { "sshKey": sshkey }

if args.password:
    credentials = { "password": args.password }

urldict['username'] = username
urldict['hostnames[]'] = hostnames
urldict['port'] = port
if 'sshKey' in credentials:
    urldict['credentials[sshKey]'] = credentials['sshKey']
elif 'password' in credentials:
    urldict['credentials[password]'] = credentials['password']

print(urlencode(urldict, True))
