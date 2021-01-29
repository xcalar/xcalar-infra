import argparse
from utilities.jenkins_log import jenkins_fetcher
from utilities.jenkins_parser import MyHTMLParser
from utilities.mysql_connect import insert, insert_info
from getpass import getpass

# ex:
# python app.py -u mchan -s 40137 -e 40140 -p
# Password: xxxx
parser = argparse.ArgumentParser(description='Parse Jenkins logs and store into MySQL')
parser.add_argument('-u', '--username', type = str, metavar='', required=True, help='Jenkins login Name')
parser.add_argument('-p', '--secure_password',  required=True, action='store_true', dest='password', help='Jenkins login Password')
parser.add_argument('-j', '--job_name', type = str, metavar='', default='XCETest', required=False, help='Jenkins Job Name')
parser.add_argument('-s', '--start_build_number', type = int, metavar='', required=True, help='Start Build Number')
parser.add_argument('-e', '--end_build_number', type = int, metavar='', required=True, help='End Build Number')
args = parser.parse_args()

if __name__ == '__main__':
    user = args.username
    if args.password:
        password = getpass()

    job_name = args.job_name
    jenkins = jenkins_fetcher('http://jenkins.int.xcalar.com', 'mchan', 'Welc{0}me1;')

    # ======================
    # start range
    # ======================
    # for build_number in reversed(range(40137, 45168)):
    for build_number in reversed(range(args.start_build_number, args.end_build_number)):
        # --------------------
        # 1. Insert build info
        # --------------------
        info = jenkins.fetch_job_build_info(job_name, build_number)
        if info is None:
            continue

        timestamp = info['test_timestamp']
        slave = info['builtOn']
        insert_info(info)
        # --------------
        # 2.featch log
        # --------------
        logs = jenkins.fetch_log(job_name, build_number)

        # --------------
        # 3.parse log
        # --------------
        parser = MyHTMLParser( timestamp, build_number, slave )
        for line in logs:
            if 'PASS' in line.upper():
                parser.feed(line)

            elif 'FAILED' in line.upper():
                if line:
                    parser.feed(line)

            elif 'SKIP' in line.upper():
                pass
                if line:
                    parser.feed(line)
            elif 'S CALL     ' in line.upper():     # slowest 10 test durations
                # '<span class="timestamp"><b>07:22:31</b> </span>179.79s call     test_operators.py::TestOperators::testAddManyColumns'
                parser.feed(line)
            else:
                pass

        # --------------------
        # 4. Insert logs
        # --------------------
        result = parser.get_result()
        insert(result)
