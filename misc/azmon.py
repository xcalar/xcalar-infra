"""Collect some stats from xcnodes provided as text file."""
import paramiko
import sys
import signal
import time
import multiprocessing

from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed


xcnodes = []


def signal_handler(signal, frame):
    """Handle Ctrl+C and gracefully exit."""
    map(lambda xcnode: xcnode.fd.close(), xcnodes)
    print 'Exiting program!'
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)


class XcNode:
    """XcNode class."""

    def __init__(self, hostname, username, password, fd, client, port):
        """Create xcnode object."""
        self.hostname = hostname
        self.username = username
        self.password = password
        self.client = client
        self.fd = fd
        self.port = port


def create_ssh_handle(xcnode):
    """Create ssh handle to xcnode."""
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.WarningPolicy)

    try:
        client.connect(
                hostname=xcnode.hostname,
                username=xcnode.username,
                password=xcnode.password,
                port=int(xcnode.port)
                )
        xcnode.fd.write('ssh\'ed to {} @ {}\n'.format(
            xcnode.hostname, datetime.now()))
    except Exception as e:
        print e
        client = None

    xcnode.client = client

    return xcnode


def collect_stats(xcnode, cmds):
    """Collect stats from xcnode."""
    output = ''

    if not xcnode.client:
        print 'ssh session does not exist for {}'.format(xcnode.host)
        return output

    for cmd in cmds:
        stdin, stdout, stderr = xcnode.client.exec_command(cmd)
        out = stdout.read()
        outerr = stderr.read()
        xcnode.fd.write('{} run @ {}\n'.format(cmd, datetime.now()))
        xcnode.fd.write('stdout:\n============:\n{}\n'.format(out))
        if outerr:
            xcnode.fd.write('stderr\n===========:\n{}\n'.format(outerr))
        output += out + '\n'
        output += outerr + '\n'
        xcnode.fd.flush()

    return output


def create_handles(xcnodes):
    """Create ssh handles to all xcnodes."""
    futures = {}
    cpu_count = multiprocessing.cpu_count()

    with ThreadPoolExecutor(max_workers=cpu_count) as executor:
        for xcnode in xcnodes:
            futures[executor.submit(create_ssh_handle, xcnode)] = xcnode

        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                print e
                raise

    executor.shutdown(wait=True)


def collect_all_stats(xcnodes, cmds):
    """Parallely collect stats from all xcnodes."""
    futures = {}
    cpu_count = multiprocessing.cpu_count()

    with ThreadPoolExecutor(max_workers=cpu_count) as executor:
        for xcnode in xcnodes:
            futures[executor.submit(collect_stats, xcnode, cmds)] = xcnode

        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                print e
                raise

    executor.shutdown(wait=True)


def parse_file(infile):
    """Parse some file and return each line as list."""
    global xcnodes

    try:
        with open(infile, 'r') as f:
            for line in f:
                if line:
                    try:
                        hostname, username, password, port = \
                                line.strip('\n').split(',')
                    except ValueError:
                        print 'Invalid line format in file'
                        sys.exit(0)
                    fd = open('{}.log'.format(hostname), 'w')
                    host = XcNode(hostname, username, password, fd, None, port)
                    xcnodes.append(host)
    except IOError:
        print '{} not found'.format(infile)

    return xcnodes


if __name__ == '__main__':
    xchosts = parse_file('vms.txt')

    if not xchosts:
        sys.exit(0)

    create_handles(xchosts)

    while True:
        collect_all_stats(xchosts, ['/opt/xcalar/bin/xccli -c "stats 0"'])

        time.sleep(10)
