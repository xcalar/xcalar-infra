import argparse
import json
import hashlib
import time
import timeit
import sys
import os
import io
import subprocess
import signal
from datetime import datetime

from xcalar.external.LegacyApi.XcalarApi import XcalarApi
from xcalar.external.LegacyApi.Session import Session
from xcalar.external.LegacyApi.Operators import Operators
from xcalar.external.LegacyApi.Retina import Retina
from xcalar.external.LegacyApi.Export import Export

from IMDUtil import IMDOps
from prepareEnv import TestEnvironment
from validateData import IMDDataValidation

here = os.path.abspath(os.path.dirname(__file__))
datasetPath = "/freenas/imdtests/"
xcalarPython = os.path.join(os.environ.get('XLRDIR','/opt/xcalar'), "bin", "python3")
ecommDb = "ecommercedb"
transacDb = "transactionsdb"
triggerDimProg = os.path.join(here, "triggerDimsCubes.py")
queryCubeProg = os.path.join(here, "queryCube.py")

class DataGenerator(object):
    def __init__(self, args):
        self.xcApi = XcalarApi(bypass_proxy = True)
        self.username = args.user
        try:
            self.session = Session(self.xcApi, self.username, self.username,
                    None, True, sessionName="ImdTests")
        except Exception as e:
            print("Could not set session for %s" % (self.username))
            raise e
        try:
            self.session.activate()
        except:
            print("Session already active!")
        self.xcApi.setSession(self.session)
        self.retina = Retina(self.xcApi)
        self.export = Export(self.xcApi)
        self.op = Operators(self.xcApi)

        self.dbName = args.db
        self.numBaseRows = args.numBaseRows
        self.numUpdateRows = args.numUpdateRows
        self.numUpdates = args.numUpdates
        self.bases = args.bases
        self.updates = args.updates
        self.updateSleep = args.updateSleep
        self.numThreads = args.numThreads
        self.validateData = args.validateData
        self.exportUrl = args.exportUrl
        self.getSchema("{}.json".format(self.dbName))
        self.dbImportTarget = "pgDb_{}_import".format(self.dbName)
        self.dbExportTarget = "pgDb_{}_export".format(self.dbName)
        if args.env == 'local':
            self.importTargetName = "Default Shared Root"
            self.exportTargetName = "Default"
            self.imd = True
        elif args.env == 's3':
            self.importTargetName = "s3DatagenImport"
            self.exportTargetName = "s3DatagenExport"
            self.imd = True
        elif args.env == 'postgresqldb':
            self.exportTargetName = self.dbExportTarget
            self.imd = False
        testEnvParams = {}
        testEnvParams['exportUrl'] = args.exportUrl
        testEnvParams['env'] = args.env
        testEnvParams['validateData'] = self.validateData
        if self.validateData or args.env == 'postgresqldb':
            dbArgs = ["dbHost", "dbPort", "dbUser", "dbPass", "db"]
            for arg in dbArgs:
                if hasattr(args, arg):
                    testEnvParams[arg] = getattr(args, arg)
                elif hasattr(self, arg):
                    testEnvParams[arg] = getattr(self, arg)
                else:
                    print("Specify {} value".format(arg))
        self.testEnv = TestEnvironment(self.xcApi, **testEnvParams)
        self.testEnv.run()
        self.imdOps = IMDOps(self.xcApi)
        self.dataValidate = IMDDataValidation(self.xcApi, self.dbImportTarget)

    def getSchema(self, schemaName):
        self.schema = None
        with open(os.path.join(here, "schemas", schemaName)) as f:
            self.schema = json.load(f)
        #helper variable to get cols names as list
        self.tabColsMap = {}
        for tab in self.schema:
            cols = [col['name'] for col in self.schema[tab]['columns']]
            self.tabColsMap[tab] = cols

    def genData(self, iter=None):
        if iter:
            print("="*30, "Running iteration:", iter, "="*30)
        print("Generating data for tables with", self.dbName)
        params = ['numRows', 'exportTargetName', 'fileName']
        dfParams = []
        for param in params:
            dfParams.append(
                    {
                        "paramName":param,
                        "paramValue":str(getattr(self, param))
                    }
                )
        self.retina.execute(self.dbName, dfParams)
        print("Data generation with {}, done!".format(self.dbName))

    def doIMD(self):
        for tab in self.schema:
            print("Started {} imd generation and validation".format(tab))
            path = os.path.join(self.exportUrl, tab, self.fileName)
            self.schema[tab]["path"] = path
            self.schema[tab]["targetName"] = self.importTargetName
            tableName = tab
            if self.fileName == "base":
                self.imdOps.createPubTables({tab: self.schema[tab]})
            else:
                self.imdOps.applyUpdates({tab: self.schema[tab]})
                tableName = tab + "_update"
            if self.validateData:
                cols = self.tabColsMap[tab]
                self.exportChangesToDB(tableName, tab, cols)
                self.dataValidate.compareData(tab, self.schema[tab])
            try:
                self.op.dropTable('*')
            except:
                pass
            print("="*60)

    def exportChangesToDB(self, tableName, fileName, cols):
        self.export.csv(tableName, cols,
                    headerType="every",
                    fileName=fileName+".csv",
                    createType="deleteAndReplace",
                    targetName=self.dbExportTarget,
                    isUdf=True
                    )
        self.op.dropTable(tableName)
        print("Successfully exported to DB {}".format(fileName))

    def printSubprocessOutput(self, reader, prName):
        output = reader.read()
        if not output:
            print("No logs from {} sub-process".format(prName))
            return
        print("="*80)
        print("Sub-process {} output:".format(prName))
        sys.stdout.write(output)
        print("="*80)

    def main(self):
        print("====================================")
        print(datetime.now().strftime("%d %b %Y %H:%M:%S"))
        print("====================================")
        if self.bases:
            self.fileName = "base"
            self.numRows = self.numBaseRows
            self.genData()
            self.doIMD()
        if not self.updates:
            return
        #trigger the slow changing and cubes asyncly
        triggerCubeCmd = "{} {} -u {} -i \"{}\" -p {} -c {}".format(
                        xcalarPython, triggerDimProg, self.username,
                        "Default Shared Root", datasetPath, self.dbName)
        if self.dbName == ecommDb:
            cubeName = 'ecommcube'
        elif self.dbName == transacDb:
            cubeName = 'transcube'
        else:
            raise ValueError("Invalid data generation retina")
        queryCubeCmd = "{} {} -u {} -c {} --numThreads {}".format(
                        xcalarPython, queryCubeProg,
                        self.username, cubeName, self.numThreads)
        iter = 1
        pr1LogFile = "triggerCube.out"
        pr2LogFile = "queryCube.out"
        with io.open(pr1LogFile, 'w') as pr1Writer,\
            io.open(pr1LogFile, 'r') as pr1Reader,\
            io.open(pr2LogFile, 'w') as pr2Writer,\
            io.open(pr2LogFile, 'r') as pr2Reader:
            pr1 = subprocess.Popen(triggerCubeCmd,
                           stdout=pr1Writer,
                           shell=True)
            pr2 = subprocess.Popen(queryCubeCmd,
                           stdout=pr2Writer,
                           shell=True)
            pr1Name = pr1LogFile.split('.')[0]
            pr2Name = pr2LogFile.split('.')[0]
            while pr1.poll() is None and pr2.poll() is None and self.numUpdates > 0:
                self.fileName = "updates/{}".format(int(time.time()))
                self.numRows = self.numUpdateRows
                self.genData(iter)
                if self.imd:
                    self.doIMD()
                self.numUpdates -= 1
                self.printSubprocessOutput(pr1Reader, pr1Name)
                self.printSubprocessOutput(pr2Reader, pr2Name)
                iter += 1
                time.sleep(self.updateSleep)
            self.printSubprocessOutput(pr1Reader, pr1Name)
            self.printSubprocessOutput(pr2Reader, pr2Name)
        print("Stopped applying updates, stopping the other processes!")
        if pr1.poll():
            if pr1.returncode != 0:
                raise ValueError("{} failed!".format(pr1Name))
        if pr2.poll():
            if pr2.returncode != 0:
                raise ValueError("{} failed!".format(pr2Name))
        if pr1.poll() is None:
            print("Terminating process which triggers dimension and cube updates")
            pr1.terminate()
        if pr2.poll() is None:
            print("Terminating process which queries the cube")
            pr2.terminate()

if __name__ == '__main__':
    argParser = argparse.ArgumentParser(description="Prime Xcalar cluster with\
        imd tables and cubes generation and updates running")
    argParser.add_argument('--user', '-u', help="Xcalar User", required=True,
        default="admin")
    argParser.add_argument('--numBaseRows', help="Number of rows to generate",
        required=False, default=2000, type=int)
    argParser.add_argument('--exportUrl', help="Where to export the data",
        required=True, default="/mnt/xcalar/export/")
    argParser.add_argument('--db', '-d', help="what cube data to generate",
                        choices=[ecommDb, transacDb], required=True)
    argParser.add_argument('--env', help="environment to import and export \
        files",choices=['local', 's3', 'postgresqldb'], required=True)
    argParser.add_argument('--bases', help="generate base table",
        action='store_true')
    argParser.add_argument('--updates', help="generate updates",
        action='store_true')
    argParser.add_argument('--numUpdates', help="number of updates, (specify \
        negative value to run infinitely)", required=False, default=1, type=int)
    argParser.add_argument('--numUpdateRows', help="update row count",
        required=False, default=20, type=int)
    argParser.add_argument('--updateSleep', help="sleep in seconds for update \
        loop", required=False, default=1, type=int)
    argParser.add_argument('--numThreads', help="number of threads to run and \
        do concurrent selects on cube", required=False, default=8)
    argParser.add_argument('--validateData', help="Validate Xcalar data with \
        postgresql data", action='store_true')
    argParser.add_argument('--dbHost', help="Host name of postgresql",
        required=False, default="mssqlserver-demos-linux")
    argParser.add_argument('--dbPort', help="port number of postgresql",
        required=False, default=5432)
    argParser.add_argument('--dbUser', help="username of database",
        required=False, default="jenkins")
    argParser.add_argument('--dbPass', help="password of database",
        required=False, default="jenkins")

    args = argParser.parse_args()
    if not args.bases and not args.updates:
        print ("neither --base nor --updates are defined\n")
        print ("one of them is required")
        sys.exit(1)
    if args.numUpdateRows <= 0 or args.numBaseRows <= 0:
        print("numUpdateRows and numBaseRows should be positive numbers\n")
        sys.exit(1)
    if args.numUpdates < 0:
        args.numUpdates = float('Inf')

    dataGenerator = DataGenerator(args)
    dataGenerator.main()
