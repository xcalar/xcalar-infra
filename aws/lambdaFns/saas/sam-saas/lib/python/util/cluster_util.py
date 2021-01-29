import requests
from urllib.parse import urlparse, urlunparse
from urllib3.exceptions import ConnectTimeoutError, ConnectionError, \
    InvalidHeader, MaxRetryError, NewConnectionError, TimeoutError, \
    ReadTimeoutError, InsecureRequestWarning
from urllib3 import disable_warnings
from socket import timeout as socketTimeout, gaierror
disable_warnings(InsecureRequestWarning)


def node_status(base_url, time_out=5):

    def poll_service(parsed_url, service, service_paths, check_struct,
                     service_result):
        service_url = parsed_url
        service_url = service_url._replace(path=service_paths[service])
        is_running = 0

        try:
            service_resp = \
                requests.get(urlunparse(service_url),
                             verify=False, timeout=time_out)
        except (ConnectTimeoutError, ConnectionError, InvalidHeader,
                MaxRetryError, NewConnectionError, TimeoutError,
                ConnectionRefusedError, ConnectionResetError,
                ConnectionAbortedError, socketTimeout, gaierror,
                ReadTimeoutError, requests.ReadTimeout,
                requests.ConnectionError) as e:
            return is_running

        if not check_struct and service_resp.status_code == 200:
            service_result['services'][service] = True
            is_running = 1

        if check_struct and service_resp.status_code == 200 and \
           service_resp.json()['status'] == "up":
            service_result['services'][service] = True
            is_running = 1

        return is_running

    result = {
        'services': {
            'caddy': False,
            'expServer': False,
            'usrnode': False,
            'mgmtd': False,
            'sqldf': False
        },
        'status': 'down'
    }

    paths_by_service = {
        'caddy': '/healthCheck',
        'expServer': '/app/service/healthCheck',
        'usrnode': '/app/service/healthCheckUsrnode',
        'mgmtd': '/app/service/healthCheckMgmtd',
        'sqldf': '/app/service/healthCheckSqldf'
    }

    parsed_url = urlparse(base_url)
    total_services = len(result['services'])
    running_services = 0

    running_services += \
        poll_service(parsed_url, 'caddy',
                     paths_by_service, False, result)

    if result['services']['caddy']:
        running_services += \
            poll_service(parsed_url, 'expServer',
                         paths_by_service, True, result)

    if result['services']['expServer']:
        for service in ['usrnode', 'mgmtd', 'sqldf']:
            running_services += \
                poll_service(parsed_url, service,
                             paths_by_service, True, result)

    if running_services == total_services:
        result['status'] = 'up'
    elif running_services > 0 and running_services < total_services:
        result['status'] = 'partial'

    return result
