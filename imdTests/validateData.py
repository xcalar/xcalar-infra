import argparse
import json
import hashlib
import os
import time
import sys

# Xcalar imports. For more information, refer to discourse.xcalar.com
from xcalar.external.LegacyApi.XcalarApi import XcalarApi
from xcalar.external.LegacyApi.Session import Session
from xcalar.external.LegacyApi.Dataset import *
from xcalar.external.LegacyApi.Operators import *

here = os.path.abspath(os.path.dirname(__file__))


class IMDDataValidation(object):
    def __init__(self, xcalarApi, dbTarget):
        self.xcApi = xcalarApi
        self.username = xcalarApi.session.username
        self.op = Operators(self.xcApi)
        self.dbTarget = dbTarget

    def getTableFromDB(self, tableName, cols):
        tablesCreated = []
        timestamp = int(time.time())
        datasetName = "{}.{}.{}".format('admin',
                                        timestamp, tableName)
        importUdf = 'default:ingestFromDatabase'
        args = {
            "query": "select * from {}".format(tableName)
        }
        datasetUrl = '/postgresqlDB'
        try:
            dataset = UdfDataset(self.xcApi, self.dbTarget,
                                 datasetUrl, datasetName,
                                 importUdf, args)
            dataset.load()
            indexTab = "{}_{}".format(tableName, timestamp)
            self.op.indexDataset(dataset.name, indexTab,
                                 "xcalarRecordNum", fatptrPrefixName=datasetName)
            tablesCreated.append(indexTab)
            evalStrs = []
            destCols = []
            for col in cols:
                if col['type'] == 'DfInt64':
                    evalStrs.append("int({}::{})".format(datasetName, col['name']))
                elif col['type'] == 'DfFloat64':
                    evalStrs.append("float({}::{})".format(datasetName, col['name']))
                else:
                    evalStrs.append("string({}::{})".format(datasetName, col['name']))
                destCols.append(col['name'])
            mapTab = "map_{}_{}".format(tableName, timestamp)
            self.op.map(indexTab, mapTab, evalStrs, destCols)
            tablesCreated.append(mapTab)
            projectTab = "project_{}_{}".format(tableName, timestamp)
            self.op.project(mapTab, projectTab, destCols)
            return projectTab
        except:
            raise
        finally:
            self.cleanUp(tablesCreated, [dataset])

    def getTableFromXcalar(self, tableName):
        selectTab = "select_{}_2_{}".format(tableName, int(time.time()))
        self.op.select(tableName, selectTab, -1, -1)
        return selectTab

    def prepareForMinusOp(self, srcTab, tableName, srcCols, prefixName=None):
        evalStr = ""
        cols = []
        unionCols = []
        colsToIgnore = ['modifieddate', 'orderdate']
        for col in srcCols[::-1]:
            if col['name'] in colsToIgnore:
                continue
            prefixedCol = "{}".format(col['name'])
            if prefixName:
                prefixedCol = "{}::{}".format(prefixName, prefixedCol)
            if evalStr != "":
                evalStr = "concat(\".Xc.\", {})".format(evalStr)
            colStr = "string({})".format(
                prefixedCol) if col['type'] != 'DfString' else prefixedCol
            s = "ifStr(exists(" + colStr + "), " + colStr + ", \"XC_FNF\")"
            if evalStr == "":
                evalStr = s
            else:
                evalStr = "concat({}, {})".format(s, evalStr)
            cols.insert(0, (prefixedCol, col['name']))
            unionCols.insert(0, XcalarApiColumnT(
                prefixedCol, col['name'], col['type']))
        unionIndexCol = tableName.rsplit("_", 1)[0] + "_combined"
        mapTab = "map_{}_{}".format(tableName, int(time.time()))
        self.op.map(srcTab, mapTab, [evalStr], [mapTab])
        indexTab = "index_{}_{}".format(tableName, int(time.time()))
        self.op.indexTable(mapTab, indexTab, mapTab, keyFieldName=mapTab)
        self.op.dropTable(mapTab)
        unionCols.insert(0, XcalarApiColumnT(
            mapTab, unionIndexCol, 'DfString'))
        return (indexTab, unionCols)

    def getTableRowCount(self, tableName):
        count = 0
        for tabMeta in self.op.tableMeta(tableName).metas:
            count += tabMeta.numRows
        return count

    def cleanUp(self, tables, datasets=[]):
        for table in tables:
            try:
                self.op.dropTable(table)
            except:
                print("Error: dropping the table", table)
        for dataset in datasets:
            try:
                dataset.delete()
            except:
                print("Error: deleting the dataset", dataset.name)

    def compareData(self, tableName, schema):
        try:
            print("Validating data for table", tableName)
            tabCreated = []
            dbTab = self.getTableFromDB(tableName, schema['columns'])
            tabCreated.append(dbTab)
            xcalarTab = self.getTableFromXcalar(tableName)
            tabCreated.append(xcalarTab)
            assert self.getTableRowCount(dbTab) == \
                    self.getTableRowCount(xcalarTab)
            (tab1, cols1) = self.prepareForMinusOp(
                dbTab, tableName + "_1", schema['columns'])
            tabCreated.append(tab1)
            (tab2, cols2) = self.prepareForMinusOp(
                xcalarTab, tableName + "_2", schema['columns'])
            tabCreated.append(tab2)
            finalTab = "Final_{}_{}".format(tableName, int(time.time()))
            self.op.union([tab1, tab2], finalTab, [cols1, cols2],
                          dedup=True, unionType=UnionOperatorT.UnionExcept)
            assert self.getTableRowCount(finalTab) == 0
            tabCreated.append(finalTab)
        except:
            raise
        finally:
            print("Cleaning the tables!")
            self.cleanUp(tabCreated)

def parseArgs(args):
    xcApi = XcalarApi(bypass_proxy=True)
    username = args.user
    userIdUnique = int(hashlib.md5(username.encode(
        "UTF-8")).hexdigest()[:5], 16) + 4000000
    try:
        session = Session(xcApi, username, username,
                          userIdUnique, True, sessionName=args.session)
    except Exception as e:
        print("Could not set session for %s" % (username))
        raise e
    try:
        session.activate()
    except:
        print("Session already active!")
    xcApi.setSession(session)
    return xcApi


if __name__ == '__main__':
    argParser = argparse.ArgumentParser(description="Data validation for imd")
    argParser.add_argument(
        '--user', '-u', help="Xcalar User", required=True, default="admin")
    argParser.add_argument(
        '--session', '-s', help="Name of session", required=True)
    argParser.add_argument(
        '--dbTarget', '-d', help="database target to connect with", required=True)
    argParser.add_argument(
        '--table', '-t', help="imd table to do data validation with database table", required=True)
    args = argParser.parse_args()

    xcApi = parseArgs(args)
    schema = None
    schemaName = "ecommTables.json"
    with open(os.path.join(here, "schemas", schemaName)) as f:
        schema = json.load(f)

    validateData = IMDDataValidation(xcApi, args.dbTarget)
    validateData.compareData(args.table, schema[args.table])
