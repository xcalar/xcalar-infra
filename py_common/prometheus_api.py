#!/usr/bin/env python3

import json
import os
import requests
import sys
import time

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration

# Quiet some annoying warnings :)
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

ENV_CONFIG = {'PROMETHEUS_QUERY_URL':
                {'required': True,
                 'default': "https://prometheus.service.consul/api/v1/query"},
              'DEFAULT_DOMAIN': {'default': 'int.xcalar.com'}}
CFG = EnvConfiguration(ENV_CONFIG)

class PrometheusAPI(object):
    def __init__(self):
        pass

    def host_metrics(self, *, host, start_time_s, end_time_s):

        period_s = end_time_s - start_time_s
        if period_s < 60:
            raise ValueError("Period {} to {} too short.  Must be >= 60s"
                             .format(start_time_s, end_time_s))

        now_s = int(time.time())
        if end_time_s > now_s:
            raise ValueError("end_time_s in the future")


        offset_s = max(now_s-end_time_s, 1) # offset can't be 0

        if '.' not in host:
            host += '.{}'.format(CFG.get('DEFAULT_DOMAIN')) # XXXrs Ick!

        returns = []

        # XXXrs - FUTURE
        #   - want cpu min/max
        #   - want memory min/max/avg

        cpu_metrics = ['cpu_avg_idle',
                       'cpu_avg_iowait',
                       'cpu_avg_irq',
                       'cpu_avg_nice',
                       'cpu_avg_softirq',
                       'cpu_avg_steal',
                       'cpu_avg_system',
                       'cpu_avg_user']

        rtn = {}
        for metric in cpu_metrics:
            query_val = '(avg(rate(node_cpu_seconds_total{{instance="{}:9100",job="node-exporter",mode="{}"}}[{}s] offset {}s)) * 100)'\
                        .format(host, metric.split('_')[-1], period_s, offset_s)


            params = {"query": query_val}
            header = {'Content-Type': 'application/x-www-form-urlencoded'}
            prom_url = CFG.get('PROMETHEUS_QUERY_URL')
            request = requests.post(prom_url, data=params, headers=header, verify=False)
            result = json.loads(request.text)

            if len(result['data']['result']) != 0:
                value = round(float(result['data']['result'][0]['value'][1]), 2)
            else:
                value = "unknown"
            rtn[metric]=value
        return rtn

if __name__ == '__main__':
    import random

    now_s = int(time.time())

    period_s = random.randint(3600, 36000)
    print("period: {}".format(period_s))
    offset_s = random.randint(0, 36000)
    print("offset: {}".format(offset_s))
    end_s = now_s - offset_s
    start_s = end_s - period_s

    papi = PrometheusAPI()
    rtn = papi.host_metrics(host = 'kvmhost4-megavm2',
                            start_time_s = start_s,
                            end_time_s = end_s)
    print(rtn)

