import json
import jenkins
import requests
from datetime import datetime


class jenkins_fetcher(object):
    def __init__(self, url, id, pw):
        self.url = url
        self.id = id
        self.pw = pw
        self.auth = (id, pw)
        self.jenkins = jenkins

    def fetch_build_timestamp( self, job_name, build_no):
        url_str = f'{self.url}/job/{job_name}/{build_no}/api/python?tree=timestamp'
        payload = ''
        headers = {"Content-Type": "application/xml"}
        r = requests.post(url_str, data=payload, auth=self.auth, headers=headers)
        data = json.loads(r.text)
        epoch =  int(data['timestamp'])/1000
        return datetime.fromtimestamp( epoch )

    def fetch_log( self, job_name, build_no ):
        url_str = f'{self.url}/job/{job_name}/{build_no}/consoleFull'
        payload = ''
        headers = {"Content-Type": "application/xml"}
        r = requests.post(url_str, data=payload, auth=self.auth, headers=headers)
        data = r.text.split('\n')
        return data

    def fetch_meta( self, job_name, build_no ):
        url_str = f'{self.url}/job/{job_name}/{build_no}'
        payload = ''
        headers = {"Content-Type": "application/xml"}
        r = requests.post(url_str, data=payload, auth=self.auth, headers=headers)
        data = r.text.split('\n')
        return data

    def fetch_slave( self, job_name, build_no ):
        server = self.jenkins.Jenkins(self.url, username=self.id, password=self.pw)
        slave = server.get_build_info(job_name, int(build_no))
        return slave['builtOn']

    def fetch_job_build_info(self, job_name, build_no):
        try:
            server = self.jenkins.Jenkins(self.url, username=self.id, password=self.pw)
            # info = server.get_job_info(job_name, int(build_no))       # this is too much and slow
            info = server.get_build_info(job_name, int(build_no))
            epoch = int(info['timestamp']) / 1000
            timestamp_obj = datetime.fromtimestamp(epoch)
            timestamp = datetime.fromtimestamp(epoch).strftime("%Y_%m_%d, %H:%M:%S.%f")

            info_dict = {
                'id' : info['id'],
                'test_timestamp' : timestamp_obj,
                'job_name' : job_name,
                'displayName' : info['displayName'],
                'building' : str(info['building']),
                'description' : info['description'] if info['description'] else '',
                'duration' : info['duration'],
                'estimatedDuration' : info['estimatedDuration'],
                'executor' : info['executor'] if info['executor'] else '',
                'fullDisplayName' : info['fullDisplayName'],
                'queueId' : info['queueId'],
                'url' : info['url'],
                'builtOn' : info['builtOn'],
                'result' : info['result']
            }
            return info_dict
        except Exception as e:
            print(f'Warning: {e}')
            pass


if __name__ == '__main__':
    jenkins = jenkins_fetcher('http://jenkins.int.xcalar.com', 'mchan', 'Welc{0}me1;' )
    # print( jenkins.fetch_job_build_info('XCETest', '45001') )
    # print( jenkins.fetch_slave('XCETest', '45001') )

    print( jenkins.fetch_build_timestamp('XCETest', '40001') )
    # print( jenkins.fetch_meta('XCETest', '45001') )
    # print( jenkins.fetch_log('XCETest', '45001') )
