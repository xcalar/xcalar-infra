import argparse
import json
import hashlib
import time
import timeit
import psycopg2
from datetime import datetime

from xcalar.external.LegacyApi.XcalarApi import XcalarApi
from xcalar.external.LegacyApi.Session import Session
from xcalar.external.LegacyApi.WorkItem import WorkItem
from xcalar.external.LegacyApi.ResultSet import ResultSet
from xcalar.external.LegacyApi.Operators import *
from xcalar.external.LegacyApi.Dataset import *
from xcalar.external.LegacyApi.WorkItem import *
from xcalar.external.LegacyApi.Udf import *
from xcalar.external.LegacyApi.Retina import *
from xcalar.external.LegacyApi.Target import Target
from xcalar.external.LegacyApi.Target2 import Target2
from xcalar.compute.coretypes.DagTypes.ttypes import *

##TODO: Add one more cube which will generate schema
##on fly and generate all the stuff dynamically
here = os.path.abspath(os.path.dirname(__file__))

class TestEnvironment(object):
    def __init__(self, xcalarApi, **kwargs):
        self.xcApi = xcalarApi
        self.username = xcalarApi.session.username
        self.op = Operators(self.xcApi)
        self.udf = Udf(self.xcApi)
        self.retina = Retina(self.xcApi)
        self.exportTarget = Target(self.xcApi)
        self.importTarget = Target2(self.xcApi)
        datasetName = None
        dataset = None

        defaultArgs = ['env', 'exportUrl', "dbHost", "dbPort", "dbUser",
            "dbPass","db", "validateData"]
        for k,v in kwargs.items():
            if k in defaultArgs:
                setattr(self, k, v)

        ##get sessionid, it is not present in session object
        ##need to workaround this way to get it
        self.sessionId = None
        for sess in xcalarApi.session.list().sessions:
            if sess.name == xcalarApi.session.name:
                self.sessionId = sess.sessionId
                break

    def uploadUdf(self, moduleName):
        print ("Uploading %s.." % (moduleName))
        with open(os.path.join(here, "udfs", moduleName+".py")) as fp:
            self.udf.addOrUpdate(moduleName, fp.read())

    def createTargets(self):
        self.uploadUdf("import_udf_ecomm")
        self.uploadUdf("import_udf_trade")
        #memory target
        self.memoryImportTarget = "memoryTarget"
        self.importTarget.add("memory", self.memoryImportTarget, {})

        if self.env == 's3':
            self.createS3Targets()
        if self.env == 'postgresqldb' or self.validateData:
            self.createDBTargets()
        print("Targets created!")

    def createS3Targets():
        #create import target
        self.importTarget.add("s3environ", "s3DatagenImport", {})
        #create export target
        udfModule="s3_export_udf"
        self.uploadUdf(udfModule)
        self.createExportTarget(targetName="s3DatagenExport",
                            udfModule=udfModule,
                            eUrl=self.exportUrl)

    def createDBTargets(self):
        ##Import target
        params = {'dbname':self.db, 'dbtype':'PG',
                'host':self.dbHost, 'port':self.dbPort,
                'psw_arguments':self.dbPass, 'psw_provider': 'plaintext',
                'uid': self.dbUser, 'auth_mode': 'None'}
        importTargetName = "pgDb_{}_import".format(self.db)
        dbExportTarget = "pgDb_{}_export".format(self.db)
        self.importTarget.add('dsn', importTargetName, params)
        ##export udf
        udfModule = 'pgdb_export_udf'
        with open(os.path.join(here, "udfs", udfModule+".py")) as fp:
            content = fp.read()
            content = content.replace('<DBNAME>', self.db)
            content = content.replace('<DBUSER>', self.dbUser)
            content = content.replace('<DBHOST>', self.dbHost)
            content = content.replace('<DBPORT>', str(self.dbPort))
            content = content.replace('<DBPASS>', self.dbPass)
            self.udf.addOrUpdate(udfModule, content)
        self.createExportTarget(targetName=dbExportTarget,
                            udfModule=udfModule,
                            eUrl="/")
        self.resetDB()

    def createExportTarget(self, targetName, udfModule, eUrl):
        try:
            self.exportTarget.removeUDF(targetName)
        except:
            pass
        try:
            exportUdfModule = "/workbook/{}/{}/udf/{}:main".\
                    format(self.username, self.sessionId, udfModule)
            self.exportTarget.addUDF(targetName,
                                eUrl,
                                exportUdfModule)
        except Exception as e:
            print("Warning: Export target creation failed with:", str(e))

    ##Will remove this once postgresql is dockerized and run locally
    def resetDB(self):
        tablesToDelete = []
        if self.db == "ecommercedb":
            tablesToDelete = ["order_items", "orders", "customer_phone",
                        "customer_address", "customers", "address"]
        params = {}
        params["dbname"] = self.db
        params["user"] = self.dbUser
        params["host"] = self.dbHost
        params["port"] = self.dbPort
        params["password"] = self.dbPass
        conn = None
        try:
            conn = psycopg2.connect(**params)
            cur = conn.cursor()
            delStatament = 'DELETE FROM public.{}'
            for tab in tablesToDelete:
                cur.execute(delStatament.format(tab))
            conn.commit()
            cur.close()
        except:
            raise
        finally:
            if conn is not None:
                conn.close()

    def loadDataset(self, numRows, importUdf, cubeName):
        timestamp = int(time.time())
        datasetName = "{}.{}.{}".format(self.username,
                    timestamp, cubeName)
        args = {}
        datasetUrl = str(numRows)
        dataset = UdfDataset(self.xcApi, self.memoryImportTarget, datasetUrl,
                datasetName, importUdf, args)
        dataset.load()
        return (dataset, datasetName)

    def getSchema(self, schemaName):
        schema = None
        with open(os.path.join(here, "schemas", schemaName)) as f:
            return json.load(f)

    def addParamsDF(self, retinaName):
        retObj = self.retina.getDict(retinaName)
        for node in retObj["query"]:
            if node['operation'] == "XcalarApiBulkLoad":
                node['args']['loadArgs']['sourceArgsList'][0]['path'] = "<numRows>"
            elif node['operation'] == "XcalarApiExport":
                node['args']['targetName'] = "<exportTargetName>"
                fileName = node['args']['fileName'].split('-')[1]
                tabName = fileName.split('.')[0]
                fileName = tabName + "/<fileName>" + ".csv"
                node['args']['fileName'] = fileName
                node['args']['createRule'] = 'deleteAndReplace'
                if self.env == "local":
                    node['args']['targetType'] = "file"
                else:
                    node['args']['targetType'] = "udf"
        self.retina.update(retinaName, retObj)

    def doUnion(self, srcTab, destTab, srcCols, prefixName=None):
        ##Doing dedup union to export only unique rows
        evalStr = ""
        cols = []
        unionCols = []
        for col in srcCols[::-1]:
            prefixedCol = "{}".format(col['name'])
            if prefixName:
                prefixedCol = "{}::{}".format(prefixName, prefixedCol)
            if evalStr != "":
                evalStr = "concat(\".Xc.\", {})".format(evalStr)
            colStr = "string({})".format(prefixedCol) if col['type'] != 'DfString' else prefixedCol
            s = "ifStr(exists(" + colStr + "), " + colStr + ", \"XC_FNF\")"
            if evalStr == "":
                evalStr = s
            else:
                evalStr = "concat({}, {})".format(s, evalStr)
            cols.insert(0, (prefixedCol, col['name']))
        mapTab = "map_{}_{}".format(destTab, int(time.time()))
        self.op.map(srcTab, mapTab, [evalStr], [mapTab])
        indexTab = "index_{}_{}".format(destTab, int(time.time()))
        self.op.indexTable(mapTab, indexTab, mapTab, keyFieldName = mapTab)
        self.op.dropTable(mapTab)
        unionCols.append(XcalarApiColumnT(mapTab, mapTab, 'DfString'))
        unionCols.append(XcalarApiColumnT(prefixName, prefixName, 'DfFatptr'))
        self.op.union([indexTab], destTab, [unionCols], dedup=True)
        self.op.dropTable(indexTab)
        return (destTab, cols)

    def genEcommDFs(self):
        retinaName = "ecommercedb"
        dataset, datasetName = self.loadDataset(numRows = 1000,
                                importUdf = "import_udf_ecomm:genData",
                                cubeName = retinaName)
        tabsCreated = ["{}_1".format(retinaName)]
        self.op.indexDataset(dataset.name, tabsCreated[0],
                "xcalarRecordNum", fatptrPrefixName=datasetName)
        schema = self.getSchema("{}.json".format(retinaName))
        destTables = []
        destColumns = []
        for tab in schema:
            tab, cols = self.doUnion(tabsCreated[0], tab,
                                schema[tab]['columns'], datasetName)
            destTables.append(tab)
            destColumns.append(cols)
        try:
            self.retina.delete(retinaName)
        except:
            pass
        self.retina.make(retinaName, destTables, destColumns)
        self.addParamsDF(retinaName)
        print("Dataflow {} creation done!".format(retinaName))
        tabsCreated.extend(destTables)
        for tab in tabsCreated:
            self.op.dropTable(tab)
        dataset.delete()

    def genTransacDfs(self):
        retinaName = "transactionsdb"
        dataset, datasetName = self.loadDataset(numRows = 1000,
                                importUdf = "import_udf_trade:genData",
                                cubeName = retinaName)
        tabsCreated = ["{}_1".format(retinaName)]
        self.op.indexDataset(dataset.name, tabsCreated[0],
                "xcalarRecordNum", fatptrPrefixName=datasetName)
        schema = self.getSchema("{}.json".format(retinaName))
        destTables = []
        destColumns = []
        for tab in schema:
            tab, cols = self.doUnion(tabsCreated[0], tab,
                                schema[tab]['columns'], datasetName)
            destTables.append(tab)
            destColumns.append(cols)
        try:
            self.retina.delete(retinaName)
        except:
            pass
        self.retina.make(retinaName, destTables, destColumns)
        self.addParamsDF(retinaName)
        print("Dataflow {} creation done!".format(retinaName))
        tabsCreated.extend(destTables)
        for tab in tabsCreated:
            self.op.dropTable(tab)
        dataset.delete()

    def run(self):
        print("Creating IMD test environment..")
        self.createTargets()
        try:
            self.op.dropTable('*')
        except:
            pass
        self.genEcommDFs()
        self.genTransacDfs()
        print("="*20, "Done", "="*20)
