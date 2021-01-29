#!/opt/xcalar/bin/python2.7

import sys
import os
import time
import getpass

import pyClient
from pyClient.XcalarApi import XcalarApi
from pyClient.Session import Session
from pyClient.WorkItem import WorkItem, WorkItemGetTableMeta, WorkItemSessionInact, WorkItemSessionSwitch, WorkItemSessionDelete
from Status.ttypes import *
from LibApisCommon.ttypes import *

class SessionReplayTest(object):
    def __init__(self, username, userIdUnique=None):
        self.xcalarApi = XcalarApi()
        self.jobStatus = 0
        if not userIdUnique:
            userIdUniqueStr = username + str(os.getpid()) + str(time.time())
            userIdUnique = hash(userIdUniqueStr) & 0xFFFFFFFF

        self.username = username
        self.userIdUnique = userIdUnique

        self.session = Session(self.xcalarApi, "SessionTest", self.username, userIdUnique, True)


    def listSessions(self, pattern):
        print "{0}".format(self.session.list(pattern))

    def activateSession(self, pattern):
        activateWorkItem = WorkItemSessionSwitch(pattern, None, False, self.username,
                                                 self.userIdUnique)
        self.jobStatus = self.xcalarApi.execute(activateWorkItem).jobStatus

    def inactivateSession(self, pattern):
        inactivateWorkItem = WorkItemSessionInact(pattern, False, self.username,
                                                 self.userIdUnique)
        self.jobStatus = self.xcalarApi.execute(inactivateWorkItem).jobStatus

    def closeSessionList(self, pattern, username):
        sessionList = self.session.list(pattern);

        for session in sessionList.sessions:
            if session.name.startswith(username) and session.name != self.session.name:
                if session.state == 'Active':
                    self.inactivateSession(session.name)
                workItem = WorkItemSessionDelete(session.name, userName=self.username,
                                         userIdUnique=self.userIdUnique)
                self.jobStatus = self.xcalarApi.execute(workItem).jobStatus

    def close(self):
        print "{0}".format(self.session.destroy())

if __name__ == "__main__":
#    xcalarUser = 'thaining@xcalar.com'
#    xcalarWorkbook = 'untitled-thaining'
    xcalarUser = 'brentlim'
    xcalarWorkbook = 'xcalar_1_2_0_RC7'
    exitCode = 0

    sessionReplay = SessionReplayTest(xcalarUser)
    try:
        print "## listing workbook session"
        sessionReplay.listSessions(xcalarWorkbook)
        print "## activate workbook session"
        sessionReplay.activateSession(xcalarWorkbook)
        print "## listing active workbook session"
        sessionReplay.listSessions(xcalarWorkbook)
        print "## deactivate workbook session"
        sessionReplay.inactivateSession(xcalarWorkbook)
        print "## activate login session"
        sessionReplay.activateSession(sessionReplay.session.name)
        print "## listing all sessions"
        sessionReplay.listSessions('*')
        print "## job status: {0}".format(sessionReplay.jobStatus)
        if sessionReplay.jobStatus != 0:
            exitCode = 1
    except Exception as e:
        print "Exception: {0}".format(e)
        sessionReplay.closeSessionList(xcalarWorkbook, xcalarUser)
        exitCode = 1

    sessionReplay.close()
    sys.exit(exitCode)
