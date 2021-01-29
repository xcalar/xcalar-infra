#!/usr/bin/env python3.6

import json
import os
import argparse

licenseKey=""

parser = argparse.ArgumentParser()

parser.add_argument("-l", "--licenseFile", help="license key file name")

args = parser.parse_args()

if args.licenseFile:
    licenseFile = open(args.licenseFile, "r")
    licenseKey = licenseFile.read().replace('\n', '')
    licenseFile.close()

print(json.dumps({"licenseKey": licenseKey}))
