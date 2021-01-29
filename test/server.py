import BaseHTTPServer
import threading
import urllib2
import socket
from argparse import ArgumentParser
from datetime import datetime
import sys

from pyvirtualdisplay import Display
from selenium import webdriver

"""
Please read README.md for env setup
"""
TEST_RESULT = None
QUIT_SIGNAL = threading.Event()
DEFAULT_SERVER_PORT = 5909

"""
Handler is http request routing implementation.
It supports opening/closing the web browser and notifying Jenkins.
"""
class Handler( BaseHTTPServer.BaseHTTPRequestHandler ):

    """
    Handles GET request
    """
    def do_GET(self):
        global TEST_RESULT
        print self.path
        params = self.parse(self.path)
        print params
        action = None
        if "name" not in params:
            return

        action = params["name"]
        if action=="start":
            """
            Sample url: http://localhost:5909/action?name=start&mode=ten&host=10.10.4.110&server=euler&port=5909&users=1
            """
            self.processStart(params)
        elif action=="close":
            """
            Sample url: http://localhost:5909/action?name=close
            """
            self.processClose(params)
        elif action=="print":
            """
            Sample url: http://localhost:5909/action?name=print&res=user0%3A%20Fail%3A%200%2C%20Pass%3A%2013%2C%20Skip%3A%204%2C%20Time%3A%2046.326s
            &callback=jQuery21309018166374230128_1484591586241&_=1484591586243
            """
            self.processPrint(params)
        elif action=="getstatus":
            """
            Sample url: http://localhost:5909/action?name=getstatus
            """
            self.processGetStatus(params)
        elif action=="setstatus":
            """
            Sample url: http://localhost:5909/action?name=setstatus
            &res=user0%3Fstatus%3AfailFail%3A%201%2C%20Pass%3A%200%2C%20Skip%3A%200%2C%20Time%3A%200s%20%2C%20Error%3A%20time%20limit%20of%205000ms%20exceeded%20in%20function%3A%20loadDS%26
            &callback=jQuery2130753973988575382_1484077385760&_=1484077385761
            """
            self.processSetStatus(params)


    def processStart(self, params):
        users = params.get("users", "1")
        mode = params.get("mode", "ten")
        server = params.get("server", socket.gethostname())
        port = params.get("port", str(DEFAULT_SERVER_PORT))
        host = params.get("host", socket.gethostname())
        testSuiteUrl = "http://"+host+"/test.html?auto=y&mode="+mode+"&host="+host+"&server="+socket.gethostname()+"%3A"+port+"&users="+users
        print testSuiteUrl
        sys.stdout.flush()
        CHROME_DRIVER_PATH = "/usr/bin/chromedriver"
        self.driver = webdriver.Chrome(CHROME_DRIVER_PATH)
        self.driver.get(testSuiteUrl)
        self.markSuccess("Started")
        print "Test started: %s" % (str(datetime.now()))
        sys.stdout.flush()
        fout = open("/tmp/chromeDriver.log", "w")
        for entry in self.driver.get_log('browser'):
            fout.write("{}\n".format(entry))
            fout.flush()


    def processClose(self, params):
        if not TEST_RESULT:
            self.markSuccess("Still running")
        else:
            self.markSuccess("Finished: "+TEST_RESULT)
            QUIT_SIGNAL.set()

    def processPrint(self, params):
        status = params["res"]
        self.markSuccess()
        print "User finishes: " + urllib2.unquote(status)
        sys.stdout.flush()

    def processGetStatus(self, params):
        if TEST_RESULT:
            self.markSuccess("==> Finished: %s <=="%(TEST_RESULT))
        else:
            self.markSuccess("Still running")
        return

    def processSetStatus(self, params):
        global TEST_RESULT
        status = params["res"]
        self.markSuccess()
        TEST_RESULT = urllib2.unquote(status)
        print "Test ended: %s" % (str(datetime.now()))
        sys.stdout.flush()


    """
    This will send back a 200 http response
    """
    def markSuccess(self, msg=""):
        self.send_response(200)
        self.send_header( 'Content-type', 'text/html' )
        self.end_headers()
        self.wfile.write(msg)

    """
    Parse the http request into a Map
    """
    def parse(self, request):
        paramMap = {}
        if request.startswith("/action?"):
            request = request[len("/action?"):]
            params = request.split("&")
            for param in params:
                key = param.split("=")[0]
                val = param.split("=")[1]
                paramMap[key] = val
        return paramMap

"""
Webserver is a wrapper class over BaseHTTPServer.
It serves as the middle layer between Jenkins and test manager.
It runs the actual handler in a separate thread which controlled by QUIT_SIGNAL.
"""
class Webserver:
    serverThread = None
    def __init__ (self, host='', port=DEFAULT_SERVER_PORT):
        self.server = BaseHTTPServer.HTTPServer( (host, port), Handler )

    def start(self):
        self.serverThread = threading.Thread(target=self.server.serve_forever)
        self.serverThread.start()

    def wait(self):
        QUIT_SIGNAL.wait()

    def shutdown(self):
        self.server.shutdown()

def main():
    parser = ArgumentParser()
    parser.add_argument("-t", "--target", dest="target", type=str,
                        metavar="<testCase>", default=None,
                        help="Target test suite manager host")
    parser.add_argument("-v", "--visible", dest="visible",
                        action="store_true", help="Run test in real browser")
    args = parser.parse_args()
    target = args.target
    if not target:
        print "Please give the target server that runs test suites: -t"
        sys.stdout.flush()
        return
    visible = args.visible

    if not visible:
        display = Display(visible=0, size=(800, 800))
        display.start()
    server = Webserver()
    server.start()
    server.wait()
    server.shutdown()
    if not visible:
        display.stop()
    

if __name__ == "__main__":
    main()
