#!/usr/bin/env python

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.


from abc import ABC, abstractmethod

import json
import logging
import os
import re
import socket
import sys
import threading
import time
import traceback

# ======================
# Sources of detail data
# ======================

class DLoggerSourceBase(ABC):
    """
    API for pulling/polling data from some underlying object.

    Either an object implements this API directly, or one or more
    objects are "wrapped" in an instance of this API.
    """
    def __init__(self, *, name, typ, detail_args):
        self.name = name
        self.typ = typ # "type" is a keyword!
        self.detail_args = detail_args

    @abstractmethod
    def basic(self):
        """
        Return dictionary containing minimum identification information,
        about the underlying object(s), things like hostname, version.
        MUST be implemented.
        """
        return {'name': self.name, 'type': self.typ}

    @abstractmethod
    def detail(self):
        """
        Return dictionary containing verbose information about the underlying
        object(s). (e.g. operational metrics).  None if not implemented.
        """
        return None


class SDKMetricsDLoggerSource(DLoggerSourceBase):
    def __init__(self, *, name, client, node=0, group_by=None):
        super().__init__(name=name,
                         typ="XCALAR_SDK_CLIENT",
                         detail_args = {'node': node, 'group_by': group_by})
        self.client = client
        self.basic_dikt = None

    def basic(self):
        if self.basic_dikt is not None:
            return self.basic_dikt
        self.basic_dikt = super().basic()
        # XXXrs - FUTURE - fill in further specifics and cache...
        return self.basic_dikt

    def detail(self):
        """
        Grab detailed metrics from the specified node and return as a dictionary.
        """
        group_by = self.detail_args['group_by']
        node = self.detail_args['node']
        valid_group_by = ['group_id', 'group_name']
        if group_by and group_by not in valid_group_by:
            raise ValueError("invalid group_by {} must be one of {}"
                             .format(group_by, valid_group_by))
        metrics = {}
        raw = self.client.get_metrics_from_node(node)

        if not raw:
            return metrics

        for metric in raw:
            m_name = metric.pop('metric_name')

            group_id = metric['group_id']
            group_name = metric['group_name']
            m_type = metric['metric_type']
            m_val = metric['metric_value']

            if not group_by:
                metrics[m_name] = metric
            elif group_by == 'group_id':
                group_id = metric.pop('group_id')
                metrics.setdefault(group_id, {})[m_name]=metric
            elif group_by == 'group_name':
                group_name = metric.pop('group_name')
                metrics.setdefault(group_name, {})[m_name]=metric

        return metrics


# =============
# D(ata) Logger
# =============

class DLogger(object):

    def __init__(self, *, test_id, log_cb=None):
        self.logger = logging.getLogger(__name__)
        self.hostname = socket.getfqdn()
        self.sources = {}
        self.test_id = test_id
        self.log_cb = log_cb

    def _log(self, msg):
        if not self.log_cb:
            self.logger.info(msg)
            return
        # If a log callback function is set,
        # call it with the formatted log message.
        self.log_cb(msg)

    def register_source(self, *, source):
        name = source.name
        if name in self.sources:
            raise ValueError("conflicting source name: {}".format(source.name))
        self.sources[name] = source

    # XXXrs - rethink data_type/data_label
    def log(self, *, data_type, data_label, dikt=None, fatal=False, detail=False):
        data = {'test_id': self.test_id,
                'hostname' : self.hostname,
                'timestamp': time.time(),
                'pid': os.getpid(),
                'tid': threading.get_ident(),
                'data_type': data_type,
                'data_label': data_label,
                'data': dikt}
        if fatal:
            data['fatal']=True
        if self.sources:
            data['sources'] = {}
            for name,source in self.sources.items():
                data['sources'][name] = {}
                data['sources'][name]['basic'] = source.basic()
                if detail:
                    data['sources'][name]['detail'] = source.detail()
        self._log("JSON_LOG_DATA: {}".format(json.dumps(data)))
        # Return a DLogEntry in case caller wants access to the
        # data filled in by the registered sources above.
        return DLogEntry(dikt=data)

    def message(self, *, msg, label="GENERIC"):
        return self.log(data_type="MESSAGE",
                        data_label=label,
                        dikt={"message": msg})

    def exception(self, *, msg, exc, fatal=True):
        label = "FATAL"
        if not fatal:
            label = "NON_FATAL"
        tb = exc.__traceback__
        dikt = {"message": msg,
                "traceback": traceback.format_tb(tb)}
        return self.log(data_type="EXCEPTION",
                        data_label=label,
                        dikt=dikt,
                        fatal=fatal)

    def start(self, *, dikt=None, detail=False):
        return self.log(data_type="TEST_START",
                        data_label="TEST_START",
                        dikt=dikt,
                        detail=detail)

    def end(self, *, dikt=None, detail=False):
        return self.log(data_type="TEST_END",
                        data_label="TEST_END",
                        dikt=dikt,
                        detail=detail)

    def step(self, *, label, dikt=None, detail=False):
        return self.log(data_type="TEST_STEP",
                        data_label=label,
                        dikt=dikt,
                        detail=detail)

    # XXXrs - FUTURE - test expected/completed planning?
    def plan(self, *, expected, enforce=True):
        raise NotImplementedError("TBS")

    # Would be "pass()", but that conflicts with keyword!
    def passed(self, *, label, dikt=None, detail=False):
        """
        Test/sub-test PASS
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="PASS",
                        dikt=dikt,
                        detail=detail)

    def failed(self, *, label, dikt=None, detail=False, fatal=False):
        """
        Test/sub-test FAIL
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="FAIL",
                        dikt=dikt,
                        detail=detail)

    def done(self, *, label, dikt=None, detail=False):
        """
        Test/sub-test completed successfully, no pass/fail indication
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="DONE",
                        dikt=dikt,
                        detail=detail)

    def skipped(self, *, label, dikt=None, detail=False):
        """
        Test/sub-test was skipped.
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="SKIP",
                        dikt=dikt,
                        detail=detail)

    def timedout(self, *, label, dikt=None, detail=False, fatal=True):
        """
        Test/sub-test timed out.  Failure by default.
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="TIMEOUT",
                        dikt=dikt,
                        detail=detail,
                        fatal=fatal)

    def aborted(self, *, label, dikt=None, detail=False, fatal=True):
        """
        Test/sub-test aborted.  Failure by default.
        """
        return self.log(data_type="TEST_RESULT",
                        data_label="ABORT",
                        dikt=dikt,
                        detail=detail,
                        fatal=fatal)

class DLogEntry(object):

    def __init__(self, *, dikt):
        self.dikt = dikt

    def __str__(self):
        return "DLogEntry type: {} label: {}"\
               .format(self.dikt.get('data_type', 'unknown'),
                       self.dikt.get('data_label', 'unknown'))

    def timestamp(self):
        return self.dikt.get('timestamp', None)

    def basic(self, *, source_name=None):
        sources = self.dikt.get('sources', None)
        if not sources:
            return None
        info = {}
        for name,dikt in sources.items():
            if 'basic' not in dikt:
                continue
            if source_name and name != source_name:
                continue
            if source_name and name == source_name:
                return dikt['basic']
            info[name] = dikt['basic']
        return info

    def detail(self, *, source_name=None):
        sources = self.dikt.get('sources', None)
        if not sources:
            return None
        info = {}
        for name,dikt in sources.items():
            if 'detail' not in dikt:
                continue
            if source_name and name != source_name:
                continue
            if source_name and name == source_name:
                return dikt['detail']
            info[name] = {}
            info[name]['basic'] = dikt.get('basic', None)
            info[name]['detail'] = dikt['detail']
        return info


class DLog(object):

    json_data_marker = re.compile(r".*JSON_LOG_DATA: (.*)")
    def __init__(self, *, log_fd):
        self.log_fd = log_fd

    def entries(self, *, start_timestamp=None,
                         end_timestamp=None,
                         data_type=None,
                         data_label=None,
                         fatal=None,
                         filter_cb=None):
        """
        Yield entries from the log optionally filtering by various attributes.
        """
        for line in self.log_fd:
            match = DLog.json_data_marker.match(line)
            if not match:
                continue
            # XXXrs - FUTURE - Implement filtering here...
            yield DLogEntry(dikt=json.loads(match.group(1)))


if __name__ == "__main__":
    # It's log, it's log... :)
    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(levelname)s - %(threadName)s - %(funcName)s - %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout)])
    logger = logging.getLogger(__name__)
    dlogger = DLogger(test_id="unit_test")
    entry = dlogger.log(data_type="DATA_TYPE", data_label="DATA_LABEL", dikt={"hello":"world"})
    print(entry)
    try:
        raise Exception('foo exception')
    except Exception as exc:
        dlogger.exception(msg="test exception", exc=exc)
    dlogger.start()
    dlogger.step(label='step 1')
    dlogger.passed(label='step 1')
    dlogger.step(label='step 2')
    dlogger.failed(label='step 2')
    dlogger.step(label='step 3')
    dlogger.skipped(label='step 3')
    dlogger.step(label='step 4')
    dlogger.done(label='step 4')
    dlogger.step(label='step 5')
    dlogger.timedout(label='step 5')
    dlogger.step(label='step 6')
    dlogger.aborted(label='step 6')
    dlogger.end()

    with open('./tests/dlogger_test.log') as fd:
        data_log = DLog(log_fd = fd)
        for entry in data_log.entries():
            print(entry)
