#!/usr/bin/env python

import optparse
import logging
import os
import datetime
import subprocess
import tempfile
import sys

from distutils.spawn import find_executable

signKeyBin = 'signKey'

def main(options):

    expirationDelta = datetime.timedelta(days=int(options.expiration))

    expirationDate = datetime.date.today() + expirationDelta

    jdbcEnabled = "false"
    if options.jdbcEnabled:
        jdbcEnabled = "true"

    license_fields = { 'Iteration': options.license_version,
                       'LicensedTo': options.licensee,
                       'ProductFamily': options.family,
                       'Product': options.product,
                       'Version': options.version,
                       'Platform': options.system,
                       'ExpirationDate': expirationDate.strftime("%Y-%b-%d"),
                       'NodeCount': options.nodecount,
                       'UserCount': options.usercount,
                       'OnExpiry': options.onexpiry,
                       'JdbcEnabled': jdbcEnabled
                   }

    if options.maxInteractiveDataSize is not None:
        license_fields["MaxInteractiveDataSize"] = options.maxInteractiveDataSize

    if (options.sigKeys):
        for key in options.sigKeys.split(','):
            if key not in license_fields:
                print ("sigKey {} is not a license field".format(key))
                sys.exit(1)

    tempkey = tempfile.NamedTemporaryFile(delete=False)

    for key in list(license_fields.keys()):
        tempkey.write('{0}={1}\n'.format(key, license_fields[key]).encode('utf-8'))

    if (options.sigKeys):
        tempkey.write('{0}={1}\n'.format('signatureKeys', options.sigKeys).encode('utf-8'))

    tempkey.close()

    signKeyFound = False
    signKeyExecutable = find_executable(signKeyBin)

    try:
        if (os.environ["SIGNKEY_BIN"] != "" and
            os.path.exists(os.environ["SIGNKEY_BIN"])):
            signKeyFound = True
            signKeyExecutable = os.environ["SIGNKEY_BIN"]
    except KeyError:
        if (signKeyExecutable != "" and
            signKeyExecutable is not None):
            signKeyFound = True
            signKeyExecutable = os.path.abspath(signKeyExecutable)

    if not signKeyFound:
        print ("signKey executable not found.")
        print ("please make sure it is in the path, or")
        print ("specified with the SIGNKEY_BIN environment variable")
        sys.exit(1)

    if (options.keypath):
        signKeyOpt = "-k"
        signKeyOptVal = options.keypath
    elif (options.keyvar):
        signKeyOpt = "-e"
        signKeyOptVal = options.keyvar

    signKeyCmd = [
        signKeyExecutable,
        signKeyOpt,
        signKeyOptVal,
        '-l',
        tempkey.name,
    ]

    pr1 = subprocess.Popen(signKeyCmd,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)

    pr = pr1

    if options.compress:
        compressCmd = [
            'gzip',
            '-c'
        ]

        pr2 = subprocess.Popen(compressCmd,
                          stdin=pr1.stdout,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)

        base64Cmd = [
            'base64',
            '-w',
            '0'
        ]

        pr3 = subprocess.Popen(base64Cmd,
                          stdin=pr2.stdout,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
        pr = pr3


    out, err = pr.communicate()

    os.remove(tempkey.name)

    if pr.returncode != 0:
        raise ValueError(err)

    print ("{}".format(out.strip().decode('utf-8')))


if __name__ == "__main__":
    parser = optparse.OptionParser(usage="usage: %prog [options]",
                                   version="%prog 0.9")

    # defaults and choices are copied from LicenseConstants.h

    parser.add_option("-k", "--keypath", dest='keypath',
                      help="path to the private key used to sign the license")
    parser.add_option("--kv", "--keyvar", dest='keyvar',
                      help="name of base64 environment variable holding private key used to sign the license")

    parser.add_option("-l", "--licversion", dest='license_version', default='2.0',
                       help="the version of the license format, example: 2.0 ")
    parser.add_option("-f", "--family", dest='family', default='Xcalar Data Platform',
                      type="choice", choices=['Xcalar Data Platform', 'Xcalar Design', 'ALL_FAMILIES'],
                      help="the Xcalar product family code, example: Xcalar Data Platform")
    parser.add_option("-p", "--product", dest='product', default='Xcalar Data Platform',
                      type="choice", choices=['Xcalar Data Platform', 'Xcalar Design CE', 'Xcalar Design EE', 'ALL_PRODUCTS'],
                      help="the Xcalar product code, example: Xcalar Data Platform")
    parser.add_option("-v", "--prodversion", dest='version', default='1.4.0',
                      help="the Xcalar product version, example 1.4.0")
    parser.add_option("-s", "--system", dest='system', default='LINUX_X64',
                      type="choice", choices=['LINUX_X64', 'MAC_OS', 'ALL_PLATFORMS'],
                      help="the product platform/system code, example: LINUX_X64")
    parser.add_option("-x", "--expiration", dest='expiration', default='30',
                      help="the term of the license -- days to expiration, example: 365")
    parser.add_option("-n", "--nodecount", dest='nodecount', default='16',
                      help="the maximum number of nodes in the cluster, example: 16")
    parser.add_option("-u", "--usercount", dest='usercount', default='8',
                      help="the maximum number of concurrent users, example: 8")
    parser.add_option('-z', '--compress', action='store_true', dest='compress',
                      help="Compress and base64 encode the license")
    parser.add_option('--sigKeys', dest='sigKeys',
                      help="Comma separated list of license keys used to sign the license")
    parser.add_option('--licensee', dest='licensee', default="Xcalar, Inc",
                      help="Who the license is for")
    parser.add_option("--onexpiry", dest="onexpiry", default="Warn",
                      type="choice", choices=["Warn", "Disable"],
                      help="When license expires, do we warn the user, or outright disable the product")
    parser.add_option("--jdbc", action="store_true", dest="jdbcEnabled",
                      help="Enable JDBC?")
    parser.add_option("--maxInteractiveDataSize", dest="maxInteractiveDataSize", type="string",
                      help="Optional. Maximum size of dataset that can be loaded in modeling mode")

    (options, args) = parser.parse_args()

    if (options.keypath and options.keyvar):
        print ("--keypath and --keyvar are both defined\n")
        print ("please use one or the other")
        sys.exit(1)

    if ((not options.keypath) and (not options.keyvar)):
        print ("neither --keypath nor --keyvar are defined\n")
        print ("one of them is required")
        sys.exit(1)

    if (options.compress):
        gzipExecutable = find_executable("gzip")
        base64Executable = find_executable("base64")

        if (gzipExecutable == "" or
            gzipExecutable is None):
            print ("gzip command is not in the path")
            print ("the --compress will not work")
            sys.exit(1)

        if (base64Executable == "" or
            base64Executable is None):
            print ("base64 command is not in the path")
            print ("the --compress will not work")
            sys.exit(1)

    main(options)
