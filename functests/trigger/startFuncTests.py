#!/usr/bin/env python2.7
import os, sys
import time
import datetime
import ast
import socket
import os.path
import ConfigParser
import psutil
import smtplib
import atexit
from threading import Thread
from argparse import ArgumentParser
import traceback
import copy
import syslog

target = ""

class Email:
    def __init__ (self, sender='eng@xcalar.com', receivers=['mjoshi@xcalar.com', 'xma@xcalar.com']):
        self.sender = sender
        self.receivers = receivers
        self.email_template = open('%s/email_template'%(current_dir_path), 'r').read()

    def send(self, build, functest, status, host, date, url, JENKINS, params, gdbserver, succeeded=True):
        if gdbserver!=None and len(gdbserver)==0:
            gdbserver = "No gdbserver found"
        try:
            self.smtpObj = smtplib.SMTP()
            self.smtpObj.connect('gmail-smtp-in.l.google.com')
            self.smtpObj.ehlo()
            prefix = "Please follow the instructions in http://wiki.int.xcalar.com/mediawiki/index.php/Field_Technology_Projects#Functional_Test_Debug_Workflow\n"
            if not succeeded:
                message = self.email_template%(functest, status, build, host, date, build, url, JENKINS, params, prefix+gdbserver)
            else:
                message = self.email_template%(functest, status, build, host, date, build, url, JENKINS, params, "")
                message = message.replace("gdbserver(s):", "")
            print message
            self.smtpObj.sendmail(self.sender, self.receivers, message)
            self.smtpObj.quit()
        except:
            host = socket.gethostname()
            log = open('%s/log/log_%s'%(target, host), 'w')
            exc_type, exc_value, exc_tb = sys.exc_info()
            error =  str(traceback.format_exception(exc_type, exc_value, exc_tb))
            syslog.syslog(syslog.LOG_ERR, "Failed to send email: "+str(error))
            log.write(error)
            log.close()
            pass

    def close(self):
        try:
            print "..."
        except:
            host = socket.gethostname()
            log = open('%s/log/log_%s'%(target, host), 'w')
            exc_type, exc_value, exc_tb = sys.exc_info()
            error =  str(traceback.format_exception(exc_type, exc_value, exc_tb))
            log.write(error)
            log.close()
            pass

class Xcalar:
    def __init__ (self, xccli="/opt/xcalar/bin/xccli"):
        self.xccli = xccli
        self.xcalar_stop_cmd = "sudo systemctl stop xcalar"
        self.xcalar_start_cmd = "sudo systemctl start xcalar"
        self.xcalar_status_cmd = "sudo systemctl status xcalar"

    def status(self):
        res = os.popen(self.xcalar_status_cmd).read()[:-1]
        print res

    def is_up(self):
        res = os.popen(self.xccli + " -c 'version'").read()[:-1]
        if "Connection refused" in res or "Backend Version" not in res:
            return False
        return True

    def get_build(self):
        try:
            res = os.popen("timeout 10s " + self.xccli + " -c 'version'").read()[:-1]
            res = res.split('\n')[5].split('Backend Version: ')[1]
        except:
            res = ""
        return res

    def gdb_mode(self):
        return len(self.get_gdbserver()) != 0

    def get_gdbserver(self):
        res = os.popen("ps -ef | grep gdbserver | grep -v grep").read()[:-1]
        return res



class FuncTest:
    def __init__ (self, testname=None, xccli="/opt/xcalar/bin/xccli"):
        self.testname = testname
        self.xccli = xccli
        self.xcalar = Xcalar(self.xccli)
        self.gdb_mode = False
        self.error = ""

    def run(self, functest_cmd):
        self.status = os.popen(functest_cmd).read()[:-1]

    def mean(self, numbers):
        return float(sum(numbers)) / max(len(numbers), 1)

    def start(self, timeout=2*3600):
        functest_cmd = "%s -c 'functests run --allNodes --testCase %s'"%(self.xccli, self.testname)
        funcTestThread = Thread(target = self.run, args = (functest_cmd, ))
        funcTestThread.daemon = True
        funcTestThread.start()
        starttime = int(time.time())
        stop = False
        self.avgCpu = self.mean(psutil.cpu_percent(interval=3, percpu=True))
        # self.avgMem = psutil.swap_memory().percent
        self.avgMem = float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0
        count = 1
        while(funcTestThread.isAlive()):
            # print "Test is still running"
            currenttime = int(time.time())
            if starttime + timeout < currenttime:
                syslog.syslog(syslog.LOG_WARNING, "Timeout, terminating the test")
                self.status = "Timedout"
                break
            elif self.xcalar.gdb_mode():
                syslog.syslog(syslog.LOG_WARNING, "gdbserver attached, exiting")
                self.status = "Error: Connection refused"
                self.gdb_mode = True
                self.error = self.xcalar.get_gdbserver()
                break
            else:
                cpu = self.mean(psutil.cpu_percent(interval=3, percpu=True))
                # mem = psutil.swap_memory().percent
                mem = float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0
                self.avgCpu = self.avgCpu*float(count)/(count+1) + float(cpu)/(count+1)
                self.avgMem = self.avgMem*float(count)/(count+1) + float(mem)/(count+1)
                count += 1
        return self.status

    def list(self):
        res = os.popen("%s -c 'functests list'"%self.xccli).read()[:-1]
        return res

    def get_params(self, cfgPath="/etc/xcalar/default.cfg"):
        res = os.popen("grep 'FuncTests' %s"%(cfgPath)).read()
        params = res.split('\n')
        active_params = []
        for param in params:
            if not param.startswith("#"):
                active_params.append(param)
        return active_params

global_all_status = None

def compare(test1, test2):
    global global_all_status
    if test1 in global_all_status and test2 not in global_all_status:
        return -1
    if test1 not in global_all_status and test2 in global_all_status:
        return 1
    if test1 not in global_all_status and test2 not in global_all_status:
        return 0
    time1 = datetime.datetime.strptime(global_all_status[test1]['start_time'], "%Y-%m-%d %H:%M:%S")
    time2 = datetime.datetime.strptime(global_all_status[test2]['start_time'], "%Y-%m-%d %H:%M:%S")
    if time1<time2:
        return 1
    if time1>time2:
        return -1
    return 0

def update_dashboard(allTests, all_status, html, host, prev_test_meta=None):
    global global_all_status
    global_all_status = all_status
    line = ""
    if prev_test_meta != None:
        if prev_test_meta['status'] == 'Succeeded':
            color = "circle_green"
        elif prev_test_meta['status'] == 'Timedout':
            color = "circle_yellow"
        else:
            color = "circle_red"
        secline = ""
        if "avgMem" in prev_test_meta:
            secline = "<tr><td>%s</td><td class='%s'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(prev_test_meta['name'],
            color, "", prev_test_meta['start_time'], prev_test_meta['stop_time'],
            "%.2f"%float(prev_test_meta['avgCpu'])+"%", "%.2f"%float(prev_test_meta['avgMem'])+"%")
    allTests = sorted(allTests, cmp=compare)
    # print allTests

    i = 0
    for status in allTests:
        if status not in all_status:
            line += "<tr><td>%s</td><td class='circle_grey'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(status,
                "", "", "", "", "")
            continue

        if all_status[status]['status'] != 'Started' and all_status[status]['status'] != 'Interrupted':
            # print all_status
            duration = all_status[status]['duration']
            duration_hour = duration / 3600
            duration_minute = (duration % 3600) / 60
            duration_second = (duration % 60)
            duration_format = str(duration_hour)+"h "+str(duration_minute)+"m "+str(duration_second)+"s"

        if all_status[status]['status'] == 'Succeeded':
            if 'avgMem' in all_status[status]:
                line += "<tr><td>%s</td><td class='circle_green'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                    "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%float(all_status[status]['avgMem'])+"%")
            else:
                line += "<tr><td>%s</td><td class='circle_green'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                    "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)+"%")
        elif all_status[status]['status'] == 'Timedout':
            if 'avgMem' in all_status[status]:
                line += "<tr><td>%s</td><td class='circle_yellow'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                    "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%float(all_status[status]['avgMem'])+"%")
            else:
                line += "<tr><td>%s</td><td class='circle_yellow'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)+"%")
        elif all_status[status]['status'] == 'Started':
            if 'avgMem' in all_status[status]:
                line += "<tr><td>%s</td><td class='circle_blue'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    "", all_status[status]['start_time'], "",
                    "", "%.2f"%float(all_status[status]['avgMem'])+"%")
            else:
                line += "<tr><td>%s</td><td class='circle_blue'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    "", all_status[status]['start_time'], "",
                    "", "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)+"%")
        elif all_status[status]['status'] == 'Interrupted':
            if 'avgMem' in all_status[status]:
                line += "<tr><td>%s</td><td class='circle_purple'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    "", all_status[status]['start_time'], "",
                    "", "%.2f"%float(all_status[status]['avgMem'])+"%")
            else:
                line += "<tr><td>%s</td><td class='circle_purple'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    "", all_status[status]['start_time'], "",
                    "", "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)+"%")
        else:
            if 'avgMem' in all_status[status]:
                line += "<tr><td>%s</td><td class='circle_red'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                    "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%float(all_status[status]['avgMem'])+"%")
            else:
                line += "<tr><td>%s</td><td class='circle_red'></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"%(all_status[status]['name'],
                    duration_format, all_status[status]['start_time'], all_status[status]['stop_time'],
                    "%.2f"%float(all_status[status]['avgCpu'])+"%", "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)+"%")

        if i==0 and prev_test_meta != None:
            line += secline
        i += 1

    indexhtml = open('%s/html/index_%s.html'%(target, host), 'w')
    indexhtml.write(html.replace('TOBE_REPLACED_FUNCTEST', line))
    indexhtml.close()

exit_execution = True
exit_allTests = None
exit_all_status = None
exit_test = None
exit_host = None
exit_html = None

@atexit.register
def goodbye():
    global exit_execution
    try:
        if exit_execution:
            exit_all_status[exit_test]['status'] = "Interrupted"
            all_status_write = open('%s/status/last_%s'%(target, exit_host), 'w')
            all_status_write.write(str(exit_all_status))
            all_status_write.close()
            update_dashboard(exit_allTests, exit_all_status, exit_html, exit_host)
            print "%s is interrupted on %s"%(exit_test, exit_host)
    except:
        pass

current_dir_path = os.path.dirname(os.path.realpath(__file__))
def init():
    if not os.path.exists(target+"/status"):
        os.makedirs(target+"/status")
    if not os.path.exists(target+"/stats"):
        os.makedirs(target+"/stats")
    if not os.path.exists(target+"/log"):
        os.makedirs(target+"/log")
    if not os.path.exists(target+"/html"):
        os.makedirs(target+"/html")

def main():
    global exit_execution
    global exit_allTests
    global exit_all_status
    global exit_test
    global exit_host
    global exit_html
    global target

    cpu = psutil.cpu_percent(interval=0.5, percpu=True)
    numCpu = len(cpu)
    mem = psutil.virtual_memory()
    totalMem = mem.total

    parser = ArgumentParser()
    parser.add_argument("-test", "--testCase", dest="testCase", type=str, action='append',
                        metavar="<testCase>", default=None,
                        help="FuncTest Name")
    parser.add_argument("-cliPath", "--cliPath", dest="cliPath", type=str,
                        metavar="<cliPath>", default="/opt/xcalar/bin/xccli",
                        help="CLI Path")
    parser.add_argument("-cfgPath", "--cfgPath", dest="cfgPath", type=str,
                        metavar="<cfgPath>", default="/etc/xcalar/default.cfg",
                        help="Config Path")
    parser.add_argument("-single", "--single", dest="single",
                        action="store_true", help="Only run functest single time")
    parser.add_argument("-silent", "--silent", dest="silent",
                        action="store_true", help="Run functest in silent mode, no emails")
    parser.add_argument("-usrnode", "--usrnode", dest="usrnode", type=str,
                        metavar="<usrnode>", default="/opt/xcalar/bin/usrnode",
                        help="Usrnode location")
    parser.add_argument("-target", "--target", dest="target", type=str,
                        metavar="<target>", default="/netstore/users/xma/dashboard",
                        help="Location for all test data")

    args = parser.parse_args()
    tests = args.testCase
    xccli = args.cliPath
    cfg = args.cfgPath
    single = args.single
    silent = args.silent
    usrnode = args.usrnode
    target = args.target
    if tests == None:
        print "Please specify --testCase"
        sys.exit(1)

    init()
    config = ConfigParser.ConfigParser()
    config.read('%s/trigger.cfg'%(current_dir_path))
    if not single:
        TIMEOUT = int(config.get('monitor', 'timeout'))
    else:
        TIMEOUT = int(config.get('monitor', 'shorttimeout'))

    host = socket.gethostname()
    try:
        customer = config.get('customer', host)
    except:
        customer = host
    JENKINS = "NONE"
    try:
        JENKINS = config.get('jenkins', host)
    except:
        pass

    while True:
        print "%s: Test set started"%(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        for test in tests:
            xcalar = Xcalar(xccli=xccli)
            if not xcalar.is_up():
                print "Xcalar is not started, exit now..."
                syslog.syslog(syslog.LOG_ERR, "Xcalar is not started, exit now...")
                sys.exit(1)
            res = FuncTest(xccli=xccli).list()
            allTests = res.split('\n')[1:]
            # print allTests
            csv = "testId,clusterId,timestamp,testname,status\n"
            if os.path.isfile('%s/status/last_%s'%(target, host)):
                all_status = ast.literal_eval(open('%s/status/last_%s'%(target, host), 'r').read())
            else:
                all_status = {}
            i = 0

            line = ""
            params = FuncTest(xccli=xccli).get_params(cfgPath=cfg)[:-1]
            if len(params) == 0:
                line += "<li>No customized params</li>\n"
            else:
                for param in params:
                    line += "<li>%s</li>\n"%(param)

            html = open('%s/html/index-customer-template.html'%(current_dir_path), 'r').read()

            if len(params) == 0:
                params = "No customized params"
            else:
                params_str = ""
                for param in params:
                    params_str += param+"\n"
                params = params_str

            try:
                html = html.replace('TOBE_REPLACED_BUILD', xcalar.get_build())
            except:
                html = html.replace('TOBE_REPLACED_BUILD', "Filed to get version")

            html = html.replace('TOBE_REPLACED_CONFIG', line)
            html = html.replace('TOBE_REPLACED_CUSTOMER', customer)
            html = html.replace('TOBE_REPLACED_HOST', host)
            html = html.replace('TOBE_REPLACED_JENKINS', JENKINS)
            html = html.replace('TOBE_REPLACED_TIMEOUT', "%sh %sm %ss"%(str(TIMEOUT/3600), str((TIMEOUT%3600)/60), str(TIMEOUT%60)))

            syslog.syslog("Starting test: " + test)
            print "Starting test: " + test
            starttime = int(time.time())
            startdate = datetime.datetime.now()
            csv = "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n"%(customer, str(startdate.strftime("%Y-%m-%d %H:%M:%S")), test, "Started", "%.2f"%0, "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0), numCpu, totalMem, xcalar.get_build(), params.replace("\n", "|").rstrip('|'))
            stats_file = open("%s/stats/stats_%s.txt"%(target, host), "a")
            stats_file.write(csv)
            stats_file.close()

            prev_status = "Not started"
            prev_test_meta = None
            if test in all_status:
                prev_status = all_status[test]['status']
                if "stop_time" in all_status[test]:
                    prev_test_meta = copy.deepcopy(all_status[test])
            prev_githash = ""
            if test in all_status and "githash" in all_status[test]:
                prev_githash = all_status[test]['githash']

            all_status[test] = {}
            all_status[test]['githash'] = xcalar.get_build()
            all_status[test]['jenkins'] = JENKINS
            all_status[test]['gdbserver'] = ''
            all_status[test]['name'] = test
            all_status[test]['start_time'] = str(startdate.strftime("%Y-%m-%d %H:%M:%S"))
            all_status[test]['status'] = "Started"
            all_status[test]['avgMem'] = "%.2f"%(float(psutil.virtual_memory().used)/psutil.virtual_memory().total*100.0)
            update_dashboard(allTests, all_status, html, host, prev_test_meta)
            all_status_write = open('%s/status/last_%s'%(target, host), 'w')
            all_status_write.write(str(all_status))
            all_status_write.close()

            exit_execution = True
            exit_allTests = allTests
            exit_all_status = all_status
            exit_test = test
            exit_host = host
            exit_html = html
            functest = FuncTest(xccli=xccli, testname=test)
            # res = functest.start(timeout=TIMEOUT)
            email = Email(sender='mjoshi@xcalar.com', receivers=['sys-eng@xcalar.com', 'xma@xcalar.com', 'mjoshi@xcalar.com'])
            res = functest.start(timeout=TIMEOUT)
            exit_execution = False

            if xcalar.gdb_mode():
                all_status[test]['gdbserver'] = functest.error

            url = ('http:/%s/html/index_%s.html'%(target, host)).replace('netstore', 'netstore.int.xcalar.com')

            if "Success" in res:
                res = "Succeeded"
                syslog.syslog("Previous status is %s and current status is %s"%(prev_status, res))
                print "Status: %s"%(res)
            elif "Timedout" in res:
                res = "Timedout"
                syslog.syslog("Previous status is %s and current status is %s"%(prev_status, res))
                print "Status: %s"%(res)
                if not single and not silent:
                    print "Sending email..."
                    email.send(all_status[test]['githash'], test, res, host,
                        all_status[test]['start_time'], url, JENKINS, params,
                        all_status[test]['gdbserver'], False)
            elif "Error: Connection refused" in res:
                res = "Failed"
                send_res = res
                if not xcalar.gdb_mode():
                    send_res = "Exited"
                syslog.syslog("Previous status is %s and current status is %s"%(prev_status, res))
                print "Status: %s"%(res)
                print all_status[test]['gdbserver']
                if not single and not silent:
                    print "Sending email..."
                    email.send(all_status[test]['githash'], test, send_res, host,
                        all_status[test]['start_time'], url, JENKINS, params,
                        all_status[test]['gdbserver'], False)
            else:
                msg = res
                all_status[test]['message']=msg
                res = "Failed"
                send_res = res
                if not xcalar.gdb_mode():
                    send_res = "Exited"
                syslog.syslog("Previous status is %s and current status is %s"%(prev_status, res))
                print "Status: %s"%(res)
                syslog.syslog("Test response: "+msg)
                print "Response: %s"%(msg)
                if not single and not silent:
                    syslog.syslog("Sending email...")
                    email.send(all_status[test]['githash'], test, send_res, host,
                        all_status[test]['start_time'], url, JENKINS, params,
                        all_status[test]['gdbserver'], False)
            email.close()

            print "average cpu is " + str(functest.avgCpu)
            print "average mem is " + str(functest.avgMem)

            endtime = int(time.time())

            all_status[test]['status'] = res
            all_status[test]['duration'] = endtime-starttime
            all_status[test]['stop_time'] = str(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
            all_status[test]['output'] = functest.status
            all_status[test]['avgCpu'] = "%.2f"%functest.avgCpu
            all_status[test]['avgMem'] = "%.2f"%functest.avgMem
            csv = "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n"%(customer, all_status[test]['stop_time'], test, res, "%.2f"%functest.avgCpu, "%.2f"%functest.avgMem, numCpu, totalMem, xcalar.get_build(), params.replace("\n", "|").rstrip('|'))
            stats_file = open("%s/stats/stats_%s.txt"%(target, host), "a")
            stats_file.write(csv)
            stats_file.close()

            update_dashboard(allTests, all_status, html, host)

            all_status_write = open('%s/status/last_%s'%(target, host), 'w')
            all_status_write.write(str(all_status))
            all_status_write.close()

            if xcalar.gdb_mode():
                syslog.syslog("gdbserver started, exit client")
                print "gdbserver started, exit client"
                syslog.syslog(functest.error)
                print functest.error
                syslog.syslog("FAILURE: " + test)
                print "FAILURE: " + test
                while True and not single:
                    time.sleep(10000)
                    continue
                print "Exiting code 1"
                sys.exit(1)

            if not xcalar.is_up() or "Failed" in res or "Timedout" in res:
                print "FAILURE: " + test
                while True and not single:
                    time.sleep(10000)
                    continue
                sys.exit(1)

            cmd = "sudo -E gdb -p $(ps -ef | grep usrnode | grep -v grep | awk '{print $2}' | head -1) -batch -ex 'thread apply all bt' " + usrnode + " | grep Thread | grep LWP | wc -l"
            res = os.popen(cmd).read()[:-1]
            try:
                res = int(res)
            except:
                res = -1
            syslog.syslog("Num of threads: %s"%(res))

        syslog.syslog("%s: Test set finished"%(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        time.sleep(10)
        if single:
            break

if __name__ == "__main__":
    try:
        main()
    except:
        host = socket.gethostname()
        log = open('%s/log/log_%s'%(target, host), 'w')
        exc_type, exc_value, exc_tb = sys.exc_info()
        error =  str(traceback.format_exception(exc_type, exc_value, exc_tb))
        print error
        syslog.syslog(error)
        log.write(error)
        log.close()
        sys.exit(1)

