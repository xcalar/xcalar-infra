import dateutil.parser
import re
from datetime import datetime
from html.entities import name2codepoint
from html.parser import HTMLParser


# -------------------
# validate time
# -------------------
def validate_iso( dt ):
    try:
        valid_datetime = dateutil.parser.parse(dt)
        return True
    except ValueError:
        return False


# -------------------
# delta by datetime
# -------------------
def calculate_delta(datetime_str1, datetime_str2): # watch out order
    dt_object_1 = datetime.strptime(datetime_str1, '%Y-%m-%d %H:%M:%S')
    dt_object_2 = datetime.strptime(datetime_str2, '%Y-%m-%d %H:%M:%S')
    time_delta = (dt_object_2 - dt_object_1)
    total_seconds = time_delta.total_seconds()
    minutes = total_seconds / 60
    return total_seconds

# -------------------
# delta by minute
# -------------------
def calculate_delta2(time_str1, time_str2): # watch out order
    dt_object_1 = datetime.strptime(time_str1, '%H:%M:%S')
    dt_object_2 = datetime.strptime(time_str2, '%H:%M:%S')
    dt_object_3 = datetime.strptime( "23:59:59", '%H:%M:%S')
    dt_object_4 = datetime.strptime( "00:00:00", '%H:%M:%S')
    time_delta = (dt_object_2 - dt_object_1)
    total_seconds = time_delta.total_seconds()
    if total_seconds < 0:
        return 86400 + total_seconds
    else:
        return total_seconds



#def calculate_delta2(time_str1, time_str2): # watch out order
#    dt_object_1 = datetime.strptime(time_str1, '%H:%M:%S')
#    dt_object_2 = datetime.strptime(time_str2, '%H:%M:%S')
#    dt_object_3 = datetime.strptime('23:59:59', '%H:%M:%S')
#
#    if dt_object_2 >= dt_object_1:
#        time_delta = (dt_object_2 - dt_object_1)
#        print(f'>= : {time_delta}')
#        return time_delta.total_seconds()
#    else:
#        time_delta = (dt_object_3 - dt_object_1) + dt_object_2
#        print(f'< : {time_delta}')
#        return time_delta.total_seconds()


# -------------------
# delta by minute (float)
# -------------------
def calculate_delta3(time_str1, time_str2): # watch out order
    dt_object_1 = datetime.strptime(time_str1, '%H:%M:%S.%f')
    dt_object_2 = datetime.strptime(time_str2, '%H:%M:%S.%f')
    time_delta = (dt_object_2 - dt_object_1)
    total_seconds = time_delta.total_seconds()
    minutes = total_seconds / 60
    return total_seconds


# -------------------
# Simple Parser
# -------------------
class MyHTMLParser(HTMLParser):
    def __init__(self, datetime_obj = None , build_number= None, slave = None):
        super().__init__()

        self.timestamp = datetime_obj
        self.date = datetime_obj.strftime('%Y-%m-%d')
        self.build_number = build_number
        self.result = []
        self.RESULT = []
        self.last_time_record = datetime_obj.strftime('%H:%M:%S')
        self.slave = slave


    def handle_starttag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if len(self.result) > 1 :
            # self.RESULT.append(self.result)
            data = self.result[0]
            parsed = []
            if 'PASS:' in data:

                data = data.replace('PASS:','').strip()
                if 'passed in' in data:
                    # 04:01:13 monitorTest.sh 0 - Test "threeNodes monitor test" passed in 22.129s
                    data_split = data.split('passed in')
                    # date, build_number, subset, delta, slave_host, status
                    parsed.append( f'{self.date} {self.result[1]}') # datetime
                    parsed.append(self.build_number)                # build_number
                    parsed.append(data_split[0])                    # subset
                    parsed.append(float( data_split[1].replace('s','')) )   # delta
                    parsed.append(self.slave)                       # slave_host
                    parsed.append('PASS')                           # status
                    self.last_time_record = self.result[1]
                    self.RESULT.append(tuple(parsed))
                    print(f'+++ {parsed}')

                elif 'passed' in data:
                    # 21:34:22 mgmtdtest.sh 61 - Test "filter" passed
                    # 03:59:59 mgmtdtest.sh 95 - Test "getRetina - iter 2 / 2" passed
                    subset = data.replace('passed', '').strip()
                    current_time = self.last_time_record if self.result[1].isspace() else self.result[1]
                    if not validate_iso(current_time): return

                    delta = calculate_delta2(self.last_time_record, current_time)
                    parsed.append(f'{self.date} {current_time}')    # datetime
                    parsed.append(self.build_number)                # build_number
                    parsed.append(subset)                           # subset
                    parsed.append(delta)                            # delta
                    parsed.append(self.slave)                       # slave_host
                    parsed.append('PASS')                           # status
                    self.last_time_record = current_time
                    self.RESULT.append(tuple(parsed))
                    print(f'--- {parsed}')

                else:
                    self.last_time_record = self.result[1]
                    pass

            elif ' PASSED ' in data:
                # 05:28:40 PASS: mgmtdtest.sh 95 - Test "importRetina" passed
                # 08:41:28 io/test_export.py::test_multiple_parquet_telecom_prefixed PASSED         [ 98%]

                subset = re.sub('PASSED\s+\[ \d+%\]', '', data.strip())
                current_time = self.last_time_record if self.result[1].isspace() else self.result[1]
                if not validate_iso(current_time): return

                delta = calculate_delta2(self.last_time_record, current_time)
                parsed.append(f'{self.date} {current_time}')        # datetime
                parsed.append(self.build_number)                    # build_number
                parsed.append(subset)                               # subset
                parsed.append(delta)                                # delta
                parsed.append(self.slave)                           # slave_host
                parsed.append('PASS')                               # status
                self.last_time_record = current_time
                self.RESULT.append(tuple(parsed))
                print(f'--- {parsed}')

            elif 'FAIL' in data:
                if 'FAIL:' in data:
                    # 01:02:11 FAIL: mgmtdtest.sh returned 1
                    current_time = self.last_time_record if self.result[1].isspace() else self.result[1]
                    if not validate_iso(current_time): return

                    delta = calculate_delta2(self.last_time_record, current_time)
                    data = data.replace('FAIL:', '').strip()
                    parsed.append(f'{self.date} {current_time}')    # date time
                    parsed.append(self.build_number)                # build_number
                    parsed.append(data)                             # subset
                    parsed.append(delta)                                # delta
                    parsed.append(self.slave)                       # slave_host
                    parsed.append('FAIL')                           # status
                    self.last_time_record = current_time
                    self.RESULT.append(tuple(parsed))
                elif ' FAILED ' in data:
                    # <span class="timestamp"><b>21:21:27</b> </span>test_dataflows_execute.py::test_execute_dataflow[/dataflowExecuteTests/linkOutLinkIn.tar.gz-Dataflow3-34] FAILED [ 11%]cat: /proc/3229/stat: No such file or directory
                    arr = data.strip().split(' FAILED ')
                    current_time = self.last_time_record if self.result[1].isspace() else self.result[1]
                    if not validate_iso(current_time): return

                    delta = calculate_delta2(self.last_time_record, current_time)
                    parsed.append(f'{self.date} {current_time}')        # date time
                    parsed.append(self.build_number)                    # build_number
                    parsed.append(arr[0])                               # subset
                    parsed.append(delta)                                # delta
                    parsed.append(self.slave)                           # slave_host
                    parsed.append('FAIL')                               # status
                    self.last_time_record = current_time
                    self.RESULT.append(tuple(parsed))
                else:
                    self.last_time_record = self.result[1]
                    pass

            elif 's call     ' in data:     # slowest 10 test durations
                # '<span class="timestamp"><b>07:22:31</b> </span>test_operators.py::TestOperators::testAddManyColumns'
                data = data.replace('s call     ', '###').strip()
                data_split = data.split('###')
                # date, build_number, subset, delta, slave_host, status
                parsed.append(f'{self.date} {self.result[1]}')          # datetime
                parsed.append(self.build_number)                        # build_number
                parsed.append(data_split[1])                            # subset
                parsed.append(data_split[0])                            # delta
                parsed.append(self.slave)                               # slave_host
                parsed.append('PASS')                                   # status
                self.last_time_record = self.result[1]
                self.RESULT.append(tuple(parsed))
                print(f'+++ {parsed}')
            else:
                self.last_time_record = self.result[1]
                pass

        self.result = []

    def handle_data(self, data):
        self.result.append(data)

    def get_result(self):
        return self.RESULT


# -------------------
# Main
# -------------------
if __name__ == '__main__':
    parser = MyHTMLParser()
    parser.feed('<span class="timestamp"><b>18:09:35</b> </span>[2020-04-30T18:09:35 -0700] Starting caddy in /tmp/caddy-1000/8443 on port 8443') # you can use multiple 'xxx' 'ccc' '3333' into the feed

    print("------------------------------------------------------------------------------------")
    parser.feed('<span class="timestamp"><b>01:06:08</b> </span>io/test_preview.py::testPreviewCorrectness[100-/home/jenkins/workspace/XCETest/buildOut/src/data/qa/csvSanity-csv-columnNameSpace.csv-30-simpleDataset-columnNameSpace.csv] PASSED [ 97%]')
    print("------------------------------------------------------------------------------------")
    parser.feed('<span class="timestamp"><b>01:06:17</b> </span>io/test_preview.py::testPreviewNotExists PASSED                          [ 98%]')
    print("------------------------------------------------------------------------------------")
    parser.feed("""'<span class="timestamp"><b>18:06:59</b> </span>Building remotely on <a href='/computer/jenskins-ssd-slave11' class='model-link'>jenskins-ssd-slave11</a> (install-test rhel7-sanity-test gerrit-review rhel7-builder) in workspace /home/jenkins/workspace/XCETest' """)

    print( parser.get_result())


    print("############")
    dt1 = '2020-01-01 01:06:08'
    dt2 = '2020-01-01 01:06:17'
    calculate_delta( dt1, dt2 )

    dt1 = '18:06:59'
    dt2 = '18:09:35'
    calculate_delta2( dt1, dt2 )

    dt1 = '18:06:59.321'
    dt2 = '18:09:35.78'
    calculate_delta3( dt1, dt2 )
