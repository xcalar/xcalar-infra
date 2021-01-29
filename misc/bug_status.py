#/usr/bin/env python
import os
import re
import smtplib
import subprocess
import sys

from collections import namedtuple
from collections import deque
from collections import defaultdict
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

SMTP_GMAIL = 'smtp.gmail.com'
SMTP_PORT = 587
BUGZ = '/usr/local/bin/bugz'
LDAP_URI = 'ldap://turing.int.xcalar.com:389'
LDAP_SEARCH = '/usr/bin/ldapsearch'
LDAP_BASE_DN = 'ou=People,dc=int,dc=xcalar,dc=com'
BUGZILLA_URL = 'http://bugs.int.xcalar.com/show_bug.cgi?id={}'

IGNORED_USERS = ['abakshi', 'blai', 'czhang', 'fchan', 'jyang', 'mjoshi',
                 'rgagneron', 'rkadam', 'sstrange', 'vjoshi']
BUG_STATUSES = ['ASSIGNED', 'IN_PROGRESS', 'IN_REVIEW']

BugInfo = namedtuple('BugInfo', 'bugid priority status summary')
UserInfo = namedtuple('UserInfo', 'userid lastname firstname fullname')


def find_users():
    usrrex = 'dn: mail=(?P<userid>\w+).*\nsn: (?P<lname>\w+)\ncn: (?P<fname>\w+)'
    cmd = '{} -H {} -x -b {} -s sub objectclass=* sn cn'. \
        format(LDAP_SEARCH, LDAP_URI, LDAP_BASE_DN)

    try:
        output = subprocess.check_output(cmd.split())
    except subprocess.CalledProcessError:
        print('ldapsearch returned non-zero exit code')
        return {}

    users = re.findall(usrrex, output)

    usrs = {userinfo.userid: userinfo 
               for userinfo in map(lambda user: 
                   UserInfo(user[0], user[1], user[2], ' '.join([user[2], user[1]])), users)}
        
    return usrs


def find_bugs(products, priorities, target=None):
    bugsinfo = defaultdict(deque)

    # XXX Figure out how to provide multiple args to bugz
    for product in products:
        for priority in priorities:
            for status in BUG_STATUSES:
                cmd = '{} search --product {} --priority {} -s {}'
                cmd = cmd.format(BUGZ, product, priority, status)
                print(cmd)
                try:
                    output = subprocess.check_output(cmd.split())
                except subprocess.CalledProcessError:
                    print('bugz returned non-zero exit code')

                lines = output.split('\n')

                for bug in lines:
                    bugrex = '(?P<bug_id>\d+)\s+(?P<assignee>\w+)\s+(?P<summary>.*$)'
                    match = re.search(bugrex, bug)
                    if match:
                        if target:
                            cmd = 'bugz get {}'.format(match.group('bug_id'))
                            try:
                                output = subprocess.check_output(cmd.split())
                            except subprocess.CalledProcessError:
                                print('bugz returned non-zero exit code')
                    
                            if "TargetMilestone: {}".format(target) not in output:
                                continue

                        buginfo = BugInfo(match.group('bug_id'), priority, 
                                          status, match.group('summary'))
                        bugsinfo[match.group('assignee')].append(buginfo)

    import pdb
    pdb.set_trace()
    return bugsinfo


def send_mail(username, password, body):
    # XXX handle exceptions
    smtp_server = smtplib.SMTP(SMTP_GMAIL, SMTP_PORT)
    smtp_server.ehlo()
    smtp_server.starttls()
    smtp_server.login(username, password)
    smtp_server.sendmail('rkadam@xcalar.com', 'rkadam@xcalar.com', body)
    smtp_server.quit()


def form_mail_body(bugsinfo, userinfo, needUserIdCol=True, needEmailId=False):
    bug_stats = {}
    msg = MIMEMultipart('alternative')
    msg['Subject'] = 'XCE daily bugs'
    msg['From'] = 'rkadam@xcalar.com'
    msg['To'] = 'rkadam@xcalar.com'
    msg['Cc'] = 'rkadam@xcalar.com'

    body = '''
    <html>
      <head>
        <style>
          table, th, tr, td {
            border: 1px solid black;
            text-align: center;
            vertical-align: middle;
            width: 100px;
          }
        </style>
      </head>
      <body>
        <p>Hello Users!<p>
        <p>Below are the list of ShowStopper bugs assigned to your name.<p>
        <br>
        <table>
          <tr>
    '''

    if needUserIdCol:
        body += '''
            <th>User</th>
        '''

    body += '''
            <th>Bug</th>
            <th>Priority</th>
            <th>Status</th>
            <th>Summary</th>
          </tr>
    '''

    for user in sorted(bugsinfo):
        bug_stats[user] = {}

        for status in BUG_STATUSES:
            bug_stats[user][status] = \
                len(filter(lambda buginfo: buginfo.status == status, bugsinfo[user]))

        if needUserIdCol:
            uname = userinfo[user].fullname
            if needEmailId:
                uname += '(' + userinfo[user].userid + ')'

            body += '''
                <tr>
                  <th rowspan="{}">{}</th>
                </tr>
            '''.format(len(bugsinfo[user]) + 1, uname) 

        for buginfo in bugsinfo[user]:
            body += '''
              <tr>
                <td><a href="{}">{}</a></td>
                <td>{}</td>
                <td>{}</td>
                <td>{}</td>
              </tr>
            '''.format(BUGZILLA_URL.format(buginfo.bugid), buginfo.bugid, 
                       buginfo.priority, buginfo.status, buginfo.summary)

    body += '</table><br><br>'
    body += '<table><tr>'

    if needUserIdCol:
        body += '<th>User</th>'

    bugstatus_stats = {}
    for status in BUG_STATUSES:
        body += '<th>{}</th>'.format(status)
        bugstatus_stats[status] = 0

    body += '<th>Total</th>'    
    body += '</tr>'

    for user in sorted(bugsinfo.keys()):
        if needUserIdCol:
            uname = userinfo[user].fullname
            if needEmailId:
                uname += '(' + userinfo[user].userid + ')'

            body += '<tr>'
            body += '<td>{}</td>'.format(uname) 
 
        for status in BUG_STATUSES:
            if needUserIdCol:
                body += '<td>{}</td>'.format(bug_stats[user][status])
            bugstatus_stats[status] += bug_stats[user][status] 

        if needUserIdCol:
            body += '<td>{}</td>'.format(sum(bug_stats[user].itervalues()))
            body += '</tr>'
   
    body += '<tr>'
    
    if needUserIdCol:
        body += '<td>Total</td>'

    for status in bugstatus_stats:
        body += '<td>{}</td>'.format(bugstatus_stats[status]) 

    body += '<td>{}</td'.format(sum(bugstatus_stats.itervalues()))
    body += '</tr>'
    body += '</table>'
 
    body += '<p>-BugzillaBot</p></body></html>'

    msg.attach(MIMEText(body, 'html'))

    return msg.as_string()


if __name__ == '__main__':
    # XXX cmd line args
    products = ['Xcalar']
    priorities = ['ShowStopper']

    username = os.environ.get('GUSER')
    password = os.environ.get('GPASSWORD')

    if not username or not password:
        print('Please setup GUSER and GPASSWORD environment variables')
        sys.exit(-1)

    userinfo = find_users()
   
    if not userinfo:
        sys.exit(-1)
 
    bugsinfo = find_bugs(products, priorities, target="1.2.2")

    if not bugsinfo:
        sys.exit(-1)

    for user in sorted(bugsinfo):
        print(user)
        for bug in bugsinfo[user]:
            print(bug)

    body = form_mail_body(bugsinfo, userinfo)

    send_mail(username, password, body)
