#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import json
import logging
import os
from pprint import pformat
import re
import requests
import subprocess
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

# XXXrs - some magic to silence unwanted (?) security chatter...
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

from py_common.env_configuration import EnvConfiguration
"""
CONFIG = EnvConfiguration({'JENKINS_HOST':     {'required': True,
                                                'default': 'jenkins.int.xcalar.com'},
                           'JENKINS_SSH_PORT': {'required': True,
                                                'type': EnvConfiguration.NUMBER,
                                                'default': 22022},
                           'USER':             {'required': True,
                                                'default': 'jenkins'}})
"""

"""
class JenkinsSSH(object):
    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def cmd(self, *, cmd):

        cargs = ["ssh"]
        cargs.append("-oPort={}".format(COFNIG.get('JENKINS_SSH_PORT')))
        cargs.append("-oUser={}".format(CONFIG.get('USER')))
        cargs.append(CONFIG.get('JENKINS_HOST'))
        cargs.append(cmd)

        # XXXrs - send stderr to DEVNULL because keep getting the following kind of noise
        #         even though otherwise all seems perfectly fine.
        #
        #org.apache.sshd.common.SshException: flush(ChannelOutputStream[ChannelSession[id=0, recipient=0]-ServerSessionImpl[rstephens@/10.10.7.25:36154]] SSH_MSG_CHANNEL_DATA) length=0 - stream is already closed
        #   at org.apache.sshd.common.channel.ChannelOutputStream.flush(ChannelOutputStream.java:169)
        #       at org.jenkinsci.main.modules.sshd.AsynchronousCommand$1.run(AsynchronousCommand.java:114)
        #           at java.lang.Thread.run(Thread.java:748)

        self.logger.debug("subprocess.run cargs: {}".format(cargs))
        cp = subprocess.run(cargs, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return cp.stdout.decode('utf-8')
"""

class JenkinsApiError(Exception):
    pass

class JenkinsREST(object):
    def __init__(self, *, host, url_root):
        self.logger = logging.getLogger(__name__)
        self.host = host
        self.url_root=url_root

    def cmd(self, *, uri):
        url = "{}{}".format(self.url_root, uri)
        self.logger.debug("GET URL: {}".format(url))
        response = requests.get(url, verify=False) # XXXrs disable verify!
        if response.status_code != 200:
            return None
        return response.text

class JenkinsJobInfo(object):
    def __init__(self, *, job_name, japi):
        self.logger = logging.getLogger(__name__)
        self.job_name = job_name
        self.japi = japi
        self.load()

    def load(self):
        self.data = self.japi.get_job_data(job_name = self.job_name)
        if not self.data:
            err = "no data for job: {}".format(self.job_name)
            self.logger.error(err)
            raise JenkinsApiError(err)

    def first_build_number(self):
        """
        Get the first known build number for a job.
        """
        first_build = self.data.get('firstBuild', None)
        if not first_build:
            self.logger.debug("no first build available")
            return None
        bnum = first_build.get('number', None)
        self.logger.debug("return: {}".format(bnum))
        return bnum

    def last_build_number(self):
        """
        Get the last known build number for a job.
        """
        last_build = self.data.get('lastBuild', None)
        if not last_build:
            self.logger.debug("no last build available")
            return None
        bnum = last_build.get('number', None)
        self.logger.debug("return: {}".format(bnum))
        return bnum

class JenkinsBuildInfo(object):

    repo_from_branch_key_pat = re.compile(r"\A(.*)_GIT_BRANCH\Z")
    commit_sha_pat = re.compile(r"\A[0-9a-f]{40}\Z")

    def __init__(self, *, job_name, build_number, japi, test_data=None):
        self.logger = logging.getLogger(__name__)
        self.job_name = job_name
        self.build_number = build_number
        self.build_url = "{}/job/{}/{}".format(japi.url_root, job_name, build_number)
        self.japi = japi
        self.test_data = test_data
        self.load()

    def load(self):
        if self.test_data:
            self.logger.info("test_data: {}".format(self.test_data))
        try:
            self.data = self.japi.get_build_data(
                                job_name = self.job_name,
                                build_number = self.build_number)
            if not self.data:
                if self.test_data:
                    self.logger.info("no build data returned, using test data")
                    self.data = self.test_data
        except Exception as e:
            if not self.test_data:
                raise e from None
            self.logger.info("exception getting build data, using test data")
            self.data = self.test_data

        if not self.data:
            err = "no data for job: {} build: {}"\
                  .format(self.job_name, self.build_number)
            self.logger.error(err)
            raise JenkinsApiError(err)

        self.logger.debug("self.data: {}".format(self.data))

    def is_done(self):
        """
        Is the job/build complete?
        """
        building = self.data.get('building', True)
        if not building:
            return True
        # no data, or was building before, refresh
        self.load()
        building = self.data.get('building', None)
        if building is None:
            err = "no building value in data for job: {} build: {}"\
                  .format(self.job_name, self.build_number)
            self.logger.error(err)
            raise JenkinsApiError(err)
        self.logger.info("job: {} build: {} building: {}"
                          .format(self.job_name, self.build_number, building))
        return not(building)

    def parameters(self):
        parameters = {}
        actions = self.data.get('actions', None)
        if not actions:
            return parameters
        for action in actions:
            if 'parameters' not in action:
                continue
            for param in action['parameters']:
                name = param.get('name', None)
                if name is None:
                    continue
                parameters[param['name']] = param.get('value', None)
            break
        return parameters

    def built_on(self):
        return self.data.get('builtOn', None)

    def start_time_ms(self):
        return self.data.get('timestamp', None)

    def duration_ms(self):
        if self.data.get('building', True):
            # Not complete.  Manufacture a duration to NOW
            start_ms = self.data.get('timestamp', None)
            if start_ms is None:
                return None
            return int(time.time()*1000)-start_ms

        return self.data.get('duration', None)

    def end_time_ms(self):
        if self.data.get('building', True):
            # Not complete.  Manufacture an end time of NOW
            return int(time.time()*1000)

        start = self.start_time_ms()
        dur = self.duration_ms()
        if start is None or dur is None:
            return None
        return start+dur

    def result(self):
        # Observed that Jenkins will report a result even
        # if building is True :/
        if self.data.get('building', True):
            return "PENDING"
        return self.data.get('result', None) or "PENDING"

    def console(self):
        """
        Return the timestamped console log for the job/build.
        Timestamps will be offset seconds to three decimal precision (ms).
        There's (apparently) no available format to dump the actual epoch
        timestamp, so will need to construct that from build start time plus
        offset.

        http://jenkins.int.xcalar.com/job/XCETest/50096/timestamps/?appendlog

        N.B.: assumes timestamp plugin in use
        """
        text = self.japi.rest.cmd(uri="/job/{}/{}/timestamps/?appendlog"
                                      .format(self.job_name, self.build_number))
        return text

    def upstream(self):
        """
        Returns a list of dictionaries identifying upstream build(s):

        [{'job_name':<upstreamProject>, 'build_number':<upstreamBuild>}, ...]
        """
        upstream = []
        for action in self.data.get('actions', []):
            causes = action.get('causes', None)
            if not causes:
                continue
            for cause in causes:
                job_name = cause.get('upstreamProject', None)
                build_number = cause.get('upstreamBuild', None)
                if job_name is None or build_number is None:
                    continue
                upstream.append({'job_name':cause.get('upstreamProject', None),
                                 'build_number':cause.get('upstreamBuild', None)})
        return upstream

    def git_branches(self):
        """
        Scan the parameters for any <repo>_GIT_BRANCH values and return
        a dictionary: {<repo>: <branch>, ...}

        Note, only named branches (not detached SHA) are returned.
        """
        self.logger.debug("start")
        rtn = {}
        for key,val in self.parameters().items():
            match = JenkinsBuildInfo.repo_from_branch_key_pat.match(key)
            if not match:
                continue
            repo = match.group(1)
            self.logger.debug("repo: \'{}\' branch: \'{}\'".format(repo, val))
            if JenkinsBuildInfo.commit_sha_pat.match(val):
                self.logger.debug("skipping detached \'{}\'".format(val))
                continue
            if repo in rtn:
                raise Exception("duplicate repo: {}".format(repo))
            rtn[repo] = val.strip()
        self.logger.debug("rtn: {}".format(rtn))
        return rtn


class JenkinsApi(object):
    def __init__(self, *, host):
        self.logger = logging.getLogger(__name__)
        self.host = host
        self.url_root="https://{}".format(host)
        self.rest = JenkinsREST(host=host, url_root=self.url_root)
        self.job_info_cache = {}
        self.build_info_cache = {}

    def list_jobs(self):
        jobs = []
        text = self.rest.cmd(uri="/api/json")
        if not text:
            return jobs
        data = json.loads(text)
        for job in data.get('jobs', []):
            name = job.get('name', None)
            if name:
                jobs.append(name)
        return jobs

    def list_hosts(self):
        hosts = []
        text = self.rest.cmd(uri="/computer/api/json")
        if not text:
            return hosts
        data = json.loads(text)
        for host in data.get('computer', []):
            name = host.get('displayName', None)
            if name:
                hosts.append(name)
        return hosts

    def get_job_data(self, *, job_name):
        """
        Return dictionary of available build data from REST_API.
        """
        text = self.rest.cmd(uri="/job/{}/api/json".format(job_name))
        if not text:
            return None
        return json.loads(text)

    def get_job_info(self, *, job_name):
        """
        Return JenkinsJobInfo instance.  Uses REST API.
        and refresh the data.
        """
        jji = self.job_info_cache.get(job_name, None)
        if jji:
            self.logger.debug("return cached info: {}".format(jji))
            return jji
            return None
        jji = JenkinsJobInfo(job_name=job_name, japi=self)
        self.job_info_cache[job_name] = jji
        self.logger.debug("return: {}".format(jji))
        return jji

    def get_build_data(self, *, job_name, build_number):
        """
        Return dictionary of available build data from REST_API.
        """
        text = self.rest.cmd(uri="/job/{}/{}/api/json".format(job_name, build_number))
        if not text:
            return None
        return json.loads(text)

    def get_build_info(self, *, job_name, build_number, test_data=None):
        """
        Return JenkinsBuildInfo instance.  Uses REST API.
        and refresh the cache.
        """
        key = "{}:{}".format(job_name, build_number)
        jbi = self.build_info_cache.get(key, None)
        if jbi:
            self.logger.debug("return cached info: {}".format(jbi))
            return jbi
        jbi = JenkinsBuildInfo(job_name=job_name,
                               build_number=build_number,
                               japi=self,
                               test_data=test_data)
        self.build_info_cache[key] = jbi
        self.logger.debug("return info: {}".format(jbi))
        return jbi


if __name__ == '__main__':
    print("Compile check A-OK!")

    cfg = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                            'JENKINS_HOST': {'default': 'jenkins.int.xcalar.com'}})

    # It's log, it's log... :)
    logging.basicConfig(level=cfg.get('LOG_LEVEL'),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)
    japi = JenkinsApi(host=cfg.get('JENKINS_HOST'))
    job_name = "DailyTests-Trunk"
    build_number = "545"
    jbi = japi.get_build_info(job_name = job_name,
                              build_number = build_number)
    print("\tresult: {}".format(jbi.result()))

    """
    hosts = japi.list_hosts()
    print("All hosts: {}".format(hosts))
    jobs = japi.list_jobs()
    print("All jobs: {}".format(jobs))

    jji = japi.get_job_info(job_name="SqlScaleTest")
    print(jji)
    first_build = jji.first_build_number()
    print("First build: {}".format(first_build))
    last_build = jji.last_build_number()
    print("Last build: {}".format(last_build))
    """

    """
    jbi = japi.get_build_info(job_name = "SqlScaleTest",
                              build_number = last_build)
    print(jbi.console())

    job_name = "XCEFuncTest"
    if job_name not in jobs:
        raise Exception("Unknown job: {}".format(job_name))
    print("Checking job: {}".format(job_name))
    jji = japi.get_job_info(job_name=job_name)
    last_build = jji.last_build_number()
    print("\tlast build: {}".format(last_build))
    jbi = japi.get_build_info(job_name = job_name,
                              build_number = last_build)
    print("\tinfo: {}".format(jbi))
    print("\tparameters: {}".format(jbi.parameters()))
    print("\tbuilt on: {}".format(jbi.built_on()))
    print("\tstart time (ms): {}".format(jbi.start_time_ms()))
    print("\tduration (ms): {}".format(jbi.duration_ms()))
    print("\tend time (ms): {}".format(jbi.end_time_ms()))
    print("\tresult: {}".format(jbi.result()))
    print("\tupstream: {}".format(jbi.upstream()))
    print("\tlast 20 build done status:")
    for i in range(last_build-20,last_build):
        try:
            bnum = i+1
            jbi = japi.get_build_info(job_name = job_name,
                                      build_number = bnum)
            print("build {} done: {}".format(bnum, jbi.is_done()))
        except Exception as e:
            print("Exception: {}".format(e))
    """
