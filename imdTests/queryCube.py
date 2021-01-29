'''
This script will concurrently queries the published cube.
Opens the resultset and cursors and deletes it.
Will be enhanced to do some JDBC queries
'''
import time
import sys
import argparse
from concurrent.futures import ProcessPoolExecutor, wait, as_completed

from xcalar.external.LegacyApi.XcalarApi import XcalarApi
from xcalar.external.LegacyApi.Session import Session
from xcalar.external.LegacyApi.Operators import Operators
from xcalar.external.LegacyApi.ResultSet import *

def initialise(args):
    global xcalarApi
    global op
    global cubeName
    global numThreads
    global workbook

    xcalarApi = XcalarApi(bypass_proxy = True)
    username = args.user
    try:
        workbook = Session(xcalarApi, username, username,
                None, True, sessionName="queryWB")
    except Exception as e:
        print("Could not set session for %s" % (username))
        raise e
    try:
        workbook.activate()
    except:
        print("Workbook already active!")
    xcalarApi.setSession(workbook)
    op = Operators(xcalarApi)

    cubeName = args.cube
    numThreads = args.numThreads

def queryPubTable(pubTab, processNum):
    start = time.time()
    print("Process {} started querying {}".format(processNum, pubTab))

    tableName = "{}_query_{}".format(pubTab, processNum)
    try:
        op.dropTable(tableName)
    except:
        pass

    numRetries = 10
    for ii in range(numRetries):
        errorOccurred = False
        try:
            op.select(pubTab, tableName, -1, -1)
            break
        except:
            errorOccurred = True
            time.sleep(1)

    if errorOccurred:
        print("Failed to do select on {}, retried {} times".format(pubTab, numRetries))
        raise

    resultSet = ResultSet(xcalarApi, tableName=tableName, maxRecords=500)
    results = []
    resultSize = 0
    for rec in resultSet:
        results.append(rec)
        resultSize += sys.getsizeof(rec)

    del(resultSet)
    del results

    try:
        op.dropTable(tableName)
    except:
        pass
    duration = time.time() - start
    print("Process {} completed querying {} in {}".format(processNum, pubTab, duration))
    sys.stdout.flush()
    return resultSize

def concurrentQueries(count, pubTab):
    ##check pubTab is published
    ##retry for 10 mins
    retry = 10
    pubTabFound = False
    while retry > 0:
        if op.listPublishedTables(pubTab).numTables == 1:
            pubTabFound = True
            break
        retry -= 1
        print("{} cube not published yet, retrying for another {} times".format(pubTab, retry))
        time.sleep(60)
    if not pubTabFound:
        raise ValueError(pubTab, "cube not published, quering failed")

    pool = ProcessPoolExecutor(count)
    futures = []
    for x in range(count):
        futures.append(pool.submit(queryPubTable, pubTab, x))

    totalSize = 0
    for x in as_completed(futures):
        totalSize += x.result()

    return totalSize

def main():
    global numThreads
    try:
        while True:
            start = time.time()
            totalSize = concurrentQueries(numThreads, cubeName)
            print("Total size queried", totalSize)
            duration = time.time() - start
            print("Total time for all processes to run", duration)
            sys.stdout.flush()
            time.sleep(5)
    except:
        raise
    finally:
        sessionCleanUp()
        sys.stdout.flush()

##Weird way of getting session state
##then do inactive and delete
def sessionCleanUp():
    print("In session cleanup")
    session = None
    global workbook
    for sess in workbook.list().sessions:
        if sess.name == workbook.name:
            session = sess
            break
    if not session:
        return
    if session.state == 'Active':
        workbook.inactivate()
    session = None
    for sess in workbook.list().sessions:
        if sess.name == workbook.name:
            session = sess
            break
    if not session:
        return
    if session.state == 'Inactive':
        workbook.delete()
    del workbook

if __name__ == '__main__':
    argParser = argparse.ArgumentParser(description="Queries the published cube")
    argParser.add_argument('--user', '-u', help="Xcalar User", required=True, default="admin")
    argParser.add_argument('--cube', '-c', help="what cube data to generate",
                        choices=['ecommcube', 'transcube'], required=True)
    argParser.add_argument('--numThreads', help="number of threads to run and do concurrent selects on cube",
                    required=False, default=16, type=int)

    args = argParser.parse_args()
    initialise(args)
    main()
