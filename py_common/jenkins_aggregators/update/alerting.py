#!/usr/bin/env python3

import logging
import os
from prometheus_client import CollectorRegistry, Gauge
from prometheus_client import push_to_gateway, delete_from_gateway
import sys

sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.mongo import JenkinsMongoDB

CFG = EnvConfiguration({'LOG_LEVEL': {'default': logging.INFO},
                        'PUSHGATEWAY_URL': {'default': 'pushgateway.nomad:9999'}})
ONE_DAY = (60*60*24)

class AlertManager(object):
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.jmdb = JenkinsMongoDB()

    def _set_alert(self, *, alert_group, alert_id, description, severity, ttl, labels=None):
        self.logger.debug("alert_id {}".format(alert_id))
        self.logger.debug("description {}".format(description))
        self.logger.debug("severity {}".format(severity))
        self.logger.debug("labels {}".format(labels))
        self.logger.debug("ttl {}".format(ttl))

        registry = CollectorRegistry()

        label_names = ['description', 'severity']
        if labels is not None:
            label_names.extend(list(labels.keys()))
        else:
            labels = {}
        labels['description'] = description
        labels['severity'] = severity

        self.logger.debug("label_names: {}".format(label_names))
        self.logger.debug("labels: {}".format(labels))

        g = Gauge(alert_group, description, label_names, registry=registry)
        g.labels(**labels).set(1)
        push_to_gateway(CFG.get('PUSHGATEWAY_URL'), job=alert_id, registry=registry)
        self.jmdb.alert_ttl(alert_group=alert_group, alert_id=alert_id, ttl=ttl)

    def info(self, *, alert_group, alert_id, description, ttl=ONE_DAY, labels=None):
        args = locals()
        args.pop('self')
        args['severity'] = "info"
        self._set_alert(**args)

    def warning(self, *, alert_group, alert_id, description, ttl=ONE_DAY, labels=None):
        args = locals()
        args.pop('self')
        args['severity'] = "warning"
        self._set_alert(**args)

    def error(self, *, alert_group, alert_id, description, ttl=ONE_DAY, labels=None):
        args = locals()
        args.pop('self')
        args['severity'] = "error"
        self._set_alert(**args)

    def critical(self, *, alert_group, alert_id, description, ttl=ONE_DAY, labels=None):
        args = locals()
        args.pop('self')
        args['severity'] = "critical"
        self._set_alert(**args)

    def clear(self, *, alert_group, alert_id):
        self.logger.debug("alert_id {}".format(alert_id))
        delete_from_gateway(CFG.get('PUSHGATEWAY_URL'), job=alert_id)
        self.jmdb.alert_ttl(alert_group=alert_group, alert_id=alert_id, ttl=None)

    def clear_expired(self):
        for alert_group, alert_id in self.jmdb.alerts_expired():
            self.logger.debug("alert_group {} alert_id {}"
                              .format(alert_group, alert_id))
            self.clear(alert_group=alert_group, alert_id=alert_id)


# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")

    import time
    from random import randrange

    # It's log, it's log... :)
    logging.basicConfig(level=CFG.get('LOG_LEVEL'),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout)])
    logger = logging.getLogger(__name__)

    """
    XXXrs: The prometheus.nomad configuration has to be modified as follows or you
           can only send one batch of test alerts and then have to wait hours to
           send another.

           Better would be to have a group-specific configuration for the test group
           but no time to fuss that just now.

       # When the first notification was sent, wait 'group_interval' to send a batch
       # of new alerts that started firing for that group.
       -  group_interval: 5m
       +  group_interval: 1m

       # If an alert has successfully been sent, wait 'repeat_interval' to
       # resend them.
       -  repeat_interval: 3h
       +  repeat_interval: 3m
    """

    ttl = 180
    mgr = AlertManager()
    mgr.critical(alert_group="alert_test", alert_id="alert1:with:colons.and.dots",
                 description="Some critical alert", ttl=ttl)
    mgr.warning(alert_group="alert_test", alert_id="alert2",
                description="Some warning alert", ttl=ttl)
    mgr.error(alert_group="alert_test", alert_id="alert3",
              description="Some error alert", ttl=ttl)
    mgr.info(alert_group="alert_test", alert_id="alert4",
             description="Info alert with extra labels", ttl=ttl,
             labels={'foo':'bar', 'binky':'bongo', 'mary': 'had a little lamb'})

    sleep_seconds = ttl+5
    logger.debug("sleeping {}s...".format(sleep_seconds))
    time.sleep(sleep_seconds)
    logger.debug("clearing expired...")
    mgr.clear_expired()
