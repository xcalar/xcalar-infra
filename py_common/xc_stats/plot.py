#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import datetime
import gzip
import json
import json_lines
import logging
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import multiprocessing
import os
import pprint
import psutil
import queue
import threading
import time

from extract import JSONExtract
from findfiles import XcalarStatsFileFinder

logger = logging.getLogger(__name__)

class MetricsData(object):
    def __init__(self):
        self.source_to_ids = {}
        self.id_to_cfg = {}
        self.node_id_to_points = {}
        self.nodes = set()
        self.data_write_lock = threading.Lock()

    def register_metric(self, *, metric_cfg):
        source = metric_cfg.source()
        metric_id = metric_cfg.metric_id()
        self.source_to_ids.setdefault(source, set()).add(metric_id)
        self.id_to_cfg[metric_id] = metric_cfg

    def sources(self):
        return list(self.source_to_ids.keys())

    def ids_for_source(self, *, source):
        return list(self.source_to_ids.get(source, []))

    def cfg_for_id(self, *, metric_id):
        return self.id_to_cfg[metric_id]

    def add_points(self, *, node, metric_id, points):
        if not len(points):
            return
        key = "{}:{}".format(node, metric_id)
        with self.data_write_lock:
            # Thread safe.
            self.nodes.add(node)
            self.node_id_to_points.setdefault(key, []).extend(points)

    def get_points(self, *, node, metric_id):
        key = "{}:{}".format(node, metric_id)
        return self.node_id_to_points.get(key, [])

    def all_nodes(self):
        return list(self.nodes)


class MetricCfg(object):
    """
    Wrapper for a metric configuration:

        {
            "source": "_SYSTEM_STATS"|"_JOB_STATS"|"csv:name",

            If "_SYSTEM_STATS" or "_JOB_STATS":

            "xy_expr": <expr>,
            -- or --
            "key_expr": <expr>,
            "val_expr": <expr>,

            "color": <str>,
            "label": <str>,
            "swapxy": <bool>,
            "ploty2": <bool>
        }
    """
    def __init__(self, *, dikt):
        self.dikt = dikt

    def source(self):
        """
        Default to "_SYSTEM_STATS" for backward compatibility.
        """
        return self.dikt.get("source", "_SYSTEM_STATS")

    def metric_id(self):
        source = self.source()
        if "xy_expr" in self.dikt:
            return("{}:xy_expr:{}".format(self.source(),
                                          self.dikt.get("xy_expr")))
        elif "key_expr" in self.dikt and "val_expr" in self.dikt:
            return("{}:key_expr:{}:val_expr:{}".format(self.source(),
                                                       self.dikt.get("key_expr"),
                                                       self.dikt.get("val_expr")))
        elif "csv:" in source:
            return(source)

        raise ValueError("can't determine metric_id from {}".format(self.dikt))


class FigureCfg(object):
    """
    Wrapper for a single-figure configuration:

        {
            figsize: (width,height),
            title: <str>,
            xlabel: <str>,

            y1label: <str>,
            y1color: <str>,

            y2label: <str>,
            y2color: <str>,

            y1range: (min, max),
            y2range: (min, max),

            metrics: [
                <MetricCfg>,
                ...
            ]
        }

        csv file is expected to contain columns:
            timestamp, node, metric-value
    """
    def __init__(self, *, parent, dikt):
        self.parent = parent
        self.dikt = dikt
        metrics = dikt.get('metrics', None)
        if not metrics:
            raise ValueError("missing or empty \"metrics\"")
        self.mcfgs = []
        for mcfg in metrics:
            self.mcfgs.append(MetricCfg(dikt=mcfg))

    def metric_configs(self):
        return self.mcfgs

    def get(self, key, default=None):
        """
        Get the value of a configuration parameter
        Fall back to parent configuration if not present
        in "our" configuration.
        """
        val = self.dikt.get(key, None)
        if val is None:
            val = self.parent.get(key, None)
        if val is None:
            return default
        return val


class FigureGroupCfg(object):
    """
    configureation for a page of matplotlib figures
    """
    def __init__(self, *, dikt, default_name=None):
        if 'name' not in dikt and default_name:
            dikt['name'] = default_name
        self.dikt = dikt
        self.figs = [FigureCfg(parent=self, dikt=d) for d in self.dikt.get('figures', [])]

    def figures(self):
        return self.figs

    def get(self, key, default=None):
        """
        Get the value of a configuration parameter
        """
        return self.dikt.get(key, default)


def get_ts(*, dt, tm, tz):

    (year, month, day) = dt.split("-")
    (hour, minute, second) = tm.split(":")

    dt = tz.localize(datetime.datetime(int(year), int(month), int(day),
                                       int(hour), int(minute), int(second)))
    return dt.timestamp()


def put_points(*, node , metric_id, points, q):
    max_points = 100 # XXXrs magic
    start = 0
    while True:
        sendpoints = points[start:start+max_points]
        if not sendpoints:
            break
        q.put({'node':node, 'metric_id':metric_id, 'points':sendpoints})
        start += max_points


def put_done(*, q):
    q.put({'done':True})


def load_system_stats_file(*, je, path, metrics_data, node, q):
    """
    Extract relevant data from a Xcalar system stats file.
    """

    with json_lines.open(path) as f:
        for dikt in f:
            for metric_id in metrics_data.ids_for_source(source="_SYSTEM_STATS"):
                mcfg = metrics_data.cfg_for_id(metric_id=metric_id).dikt
                if 'xy_expr' in mcfg:
                    points = je.extract_xy(xy_expr=mcfg.get('xy_expr'), dikt=dikt)
                elif 'key_expr' in mcfg and 'val_expr' in mcfg:
                    points = je.extract_kv(key_expr=mcfg.get('key_expr'),
                                           val_expr=mcfg.get('val_expr'), dikt=dikt)
                else:
                    raise ValueError("invalid metric config: {}".format(mcfg))
                put_points(node=node, metric_id=metric_id, points=points, q=q)


def load_csv_file(*, metric_id, path, start_ts, end_ts, nodes, q):
    """
    Extract relevant data from a csv file.
    Format is expected to be:
        <node>,<timestamp>,<metric_value>
    """

    node_to_points = {}
    with open(path) as fp:
        for line in fp:
            try:
                node,ts,val = line.strip().split(',')
            except ValueError:
                continue
            node = str(node)
            if nodes and node not in nodes:
                continue
            ts = int(ts)
            if ts < start_ts or ts > end_ts:
                continue
            try:
                val = int(val)
            except ValueError:
                val = float(val)
            node_to_points.setdefault(node, []).append((ts,val))

    for node,points in node_to_points.items():
        put_points(node=node, metric_id=metric_id, points=points, q=q)


def file_loader(*, load_args, metrics_data, q):
    """
    Runs as a process.

    Load args define which files to process.
    Extracted metrics (points) are returned to parent
    through the Queue and aggregated into the master
    MetricsData instance.
    """
    je = JSONExtract()
    for args in load_args:
        source = args['source']
        if source == "_SYSTEM_STATS":
            load_system_stats_file(je = je,
                                   metrics_data=metrics_data,
                                   path=args['path'],
                                   node=args['node'],
                                   q=q)
            continue

        if source == "_JOB_STATS":
            raise Exception('_JOB_STATS not supported')

        # Anything else is a csv file
        load_csv_file(metric_id=args['metric_id'],
                      path=args['path'],
                      start_ts=args['start_ts'],
                      end_ts=args['end_ts'],
                      nodes=args['nodes'],
                      q=q)
    put_done(q=q)


# This will run in a thread and safely merge data points
# returned by the loader process.
def get_points(*, metrics_data, p, q):
    """
    Runs as a thread.

    Each get_points thread is paired with a file_loader process and
    reads extracted points data from the "parent" end of the queue
    until a "done" message is received.

    Points data are added to the master MetricsData instance via
    the thread-safe add_points() method.

    When "done", is received (or if the queue times out) join the
    file loader process and return.
    """
    while True:
        try:
            item = q.get(True, 600) # XXXrs ad-hoc 10min timeout
            if "done" in item:
                break
            metrics_data.add_points(node=item['node'],
                                    metric_id=item['metric_id'],
                                    points=item['points'])
        except queue.Empty:
            break
    p.join()


def system_stats_load_args(*, dsh, start_ts, end_ts, nodes):
    """
    Return an array of argument structures which define the system stats
    files that need to be loaded, and the arguments required to
    extract the appropriate data.
    """

    paths_by_node = XcalarStatsFileFinder(dsh=dsh).\
                        system_stats_files(start_ts=start_ts,
                                           end_ts=end_ts,
                                           nodes=nodes)

    args = []
    for node in sorted(list(paths_by_node.keys())):
        for path in paths_by_node.get(node):
            args.append({'source': '_SYSTEM_STATS', 'node':node, 'path':path})
    return args


def csv_load_args(*, metric_id, path, start_ts, end_ts, nodes):
    """
    Return an array of argument structures which define the csv
    files that need to be loaded, and the arguments required to
    extract the appropriate data.
    """

    args = []
    paths = []
    if os.path.isdir(path):
        # Path is a directory, so iterate over contained files for anything
        # with .csv or .CSV suffix
        for fname in os.listdir(path):
            if not (fname.endswith(".csv") or fname.endswith(".CSV")):
                continue
            paths.append(os.path.join(path,fname))
    else:
        # Path is a single file.
        paths.append(path)

    for path in paths:
        args.append({'metric_id': metric_id,
                     'path': path,
                     'start_ts': start_ts,
                     'end_ts': end_ts,
                     'nodes': nodes})
    return args


def plot(*, fig_groups, dsh, plotdir,
            start_ts, end_ts, tz, nodes=None,
            csv_name_to_path):

    # Scan the configuration files to determine the specific metrics required
    # to satisfy the needs of all the figures in all the figure groups and
    # "register" the required metrics with the MetricsData instance.

    metrics_data = MetricsData()
    for fg_cfg in fig_groups:
        for fcfg in fg_cfg.figures():
            for mcfg in fcfg.metric_configs():
                metrics_data.register_metric(metric_cfg=mcfg)

    # Using the metrics requirements, determine the files that need to be loaded.

    load_args = []
    for source in metrics_data.sources():
        if source == "_SYSTEM_STATS":
            if not dsh:
                raise ValueError("--dsh required to plot system stats")
            load_args.extend(system_stats_load_args(dsh=dsh,
                                                    start_ts=start_ts,
                                                    end_ts=end_ts,
                                                    nodes=nodes))
        elif "csv:" in source:
            foo,name = source.split(':')
            path = csv_name_to_path.get(name, None)
            if not path:
                raise ValueError("no path for csv name: {}".format(name))
            load_args.extend(csv_load_args(metric_id=source, # XXXrs - special knowledge :/
                                           path=path,
                                           start_ts=start_ts,
                                           end_ts=end_ts,
                                           nodes=nodes))
        else:
            raise ValueError("unsupported metrics source: {}".format(source))


    # load_args now contains an entry for each file that needs to be loaded.
    # Divvy up the work across all our cores.

    max_procs = psutil.cpu_count() # one process per core max
    buckets = [[] for i in range(max_procs)]
    for idx,args in enumerate(load_args):
        buckets[idx%max_procs].append(args)

    # Launch file loader processes from the main thread first.
    # Once they're going, pair each one with it's own get_points thread.
    # Must happen in this order or things can deadlock. :/
    #
    # (Apparently, this is a known limitation when mixing threads/processes.)

    processes = []
    for idx,load_args in enumerate(buckets):
        if not len(load_args):
            continue
        logger.info("file_loader {} processing {} logs".format(idx, len(load_args)))
        logger.debug("load_args: {}".format(pprint.pformat(load_args)))
        q = multiprocessing.Queue()
        p = multiprocessing.Process(target=file_loader,
                                    kwargs={"metrics_data":metrics_data,
                                            "load_args":load_args,
                                            "q":q})
        p.daemon = True # Hygenic!
        p.start()
        processes.append((p,q))

    # Launch a get_points thread to service incoming data from each file_loader process.
    threads = []
    for (p,q) in processes:
        t = threading.Thread(target=get_points,
                             kwargs={"metrics_data":metrics_data, "p":p, "q":q})
        t.daemon = True # Hygenic!
        t.start()
        threads.append(t)

    # Join all the threads.
    for t in threads:
        logger.debug("joining: {}".format(t))
        t.join()

    # All the data are now loaded into the MetricsData instance.
    # Proceed with the plotting...

    now_x10 = time.time()*10
    os.makedirs(plotdir, exist_ok=True)
    for fg_cfg in fig_groups:
        fg_name = fg_cfg.get('name', 'Unknown')
        for node in sorted(metrics_data.all_nodes()):
            outpath = os.path.join(plotdir, "{}_node{}.pdf".format(fg_name, node))

            # XXXrs - FUTURE do each pdf page in a separate process?

            with PdfPages(outpath) as pdf:
                logger.info("plotting: {}".format(outpath))

                for fcfg in fg_cfg.figures():

                    fig,ax1 = plt.subplots(figsize=fcfg.get('figsize', (8.5, 5)))
                    ax1.set_xlabel(fcfg.get('xlabel', 'time (s)'))
                    ax1.set_title(fcfg.get('title', ''))
                    ax2 = None


                    y1color = fcfg.get('y1color', 'black')
                    ax1.set_ylabel(fcfg.get('y1label', ''), color=y1color)
                    y1range = fcfg.get('y1range', None)
                    if y1range:
                        ax1.axis(ymin=y1range[0], ymax=y1range[1])
                    ax1.tick_params(axis='y', labelcolor=y1color)

                    y2label = fcfg.get('y2label', None)
                    if y2label is not None:
                        ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
                        y2color = fcfg.get('y2color', 'black')
                        ax2.set_ylabel(y2label, color=y2color)
                        y2range = fcfg.get('y2range', None)
                        if y2range:
                            ax2.axis(ymin=y2range[0], ymax=y2range[1])
                        ax2.tick_params(axis='y', labelcolor=y2color)

                    for mcfg in fcfg.metric_configs():
                        metric_id = mcfg.metric_id()
                        points = metrics_data.get_points(node=node, metric_id=metric_id)
                        if not points:
                            continue
                        if mcfg.dikt.get('swapxy', False):
                            points = [(y,x) for (x,y) in points]

                        # ASS-U-ME: the x-axis is timestamps
                        plot_points = []
                        for pt in points:
                            # Best effort rescale timestamp to seconds
                            # if (presumably) in ms or us
                            ts = pt[0]
                            if ts > now_x10:
                                ts = ts/1000
                            if ts > now_x10:
                                ts = ts/1000

                            # Exclude points outside our time range
                            if ts < start_ts or ts > end_ts:
                                continue

                            plot_points.append((ts, pt[1]))

                        plot_points.sort()

                        xes = [datetime.datetime.fromtimestamp(pt[0], tz=tz) for pt in plot_points]
                        yes = [pt[1] for pt in plot_points]

                        label = mcfg.dikt.get('label', 'Unknown')
                        if mcfg.dikt.get('ploty2', False):
                            color = mcfg.dikt.get('color', y2color)
                            ax2.plot(xes, yes, color=color, label=label)
                        else:
                            color = mcfg.dikt.get('color', y1color)
                            ax1.plot(xes, yes, color=color, label=label)

                    fig.autofmt_xdate()
                    fig.legend(loc="lower left")
                    if y2label is not None:
                        fig.tight_layout()  # otherwise the right y-label is slightly clipped
                    pdf.savefig(fig)


if __name__ == "__main__":
    import argparse
    import pytz
    import sys

    # It's log, it's log... :)
    logging.basicConfig(level=logging.INFO,
                        format="'%(asctime)s - %(levelname)s - %(threadName)s - %(funcName)s - %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout)])

    argParser = argparse.ArgumentParser()
    argParser.add_argument('--cfg', required=True, type=str, action="append",
                                help='path to figure group configuration file')
    argParser.add_argument('--plotdir', required=True, type=str,
                                help='path to plots directory')
    argParser.add_argument('--dsh', default=None, type=str,
                                help='path to DataflowStatsHistory directory')

    argParser.add_argument('--start_ts', default=None, type=int,
                                help='start timestamp (s)')
    argParser.add_argument('--end_ts', default=None, type=int,
                                help='end timestamp (s)')

    argParser.add_argument('--start_date', default=None, type=str,
                                help='start date (YYYY-MM-DD)')
    argParser.add_argument('--start_time', default=None, type=str,
                                help='start time (HH:MM:SS)')
    argParser.add_argument('--end_date', default=None, type=str,
                                help='end date (YYYY-MM-DD)')
    argParser.add_argument('--end_time', default=None, type=str,
                                help='end time (HH:MM:SS)')
    argParser.add_argument('--tz', default="America/Los_Angeles", type=str,
                                help='timezone for input/display')

    argParser.add_argument('--node', default=None, type=str, action="append",
                                help='plot data only for the given node(s)')

    argParser.add_argument('--csv', default=None, type=str, action="append",
                                help='identify a csv file for plotting --csv=<name>:<path>')

    args = argParser.parse_args()

    if args.dsh and not os.path.exists(args.dsh):
        raise ValueError("dsh path {} does not exist".format(args.dsh))

    tz = pytz.timezone(args.tz)
    now = datetime.datetime.now(tz=tz)
    today = "{}-{}-{}".format(now.year, now.month, now.day)

    start_ts = args.start_ts
    if not start_ts:
        start_dt = args.start_date
        if not start_dt:
            start_dt = today
        tm = args.start_time
        if not tm:
            tm = "00:00:00"
        start_ts = get_ts(dt=start_dt, tm=tm, tz=tz)

    end_ts = args.end_ts
    if not end_ts:
        end_dt = args.end_date
        if not end_dt:
            # Same as start date then
            end_dt = start_dt
        tm = args.end_time
        if not tm:
            tm = "23:59:59"
        dt_str = "{} {}".format(end_dt, tm)
        end_ts = get_ts(dt=end_dt, tm=tm, tz=tz)

    csv_name_to_path = {}
    if args.csv:
        for csv_in in args.csv:
            try:
                name,path = csv_in.split(':')
                csv_name_to_path[name] = path
            except:
                raise ValueError("invalid --csv argument: {}".format(csv_in))

    fig_groups = []
    for cfg in args.cfg:
        default_name = os.path.basename(cfg)
        if '.' in default_name:
            default_name,ext = default_name.split('.', 1)
        with open(cfg) as fp:
            fig_groups.append(FigureGroupCfg(dikt=json.load(fp), default_name=default_name))

    plot(fig_groups=fig_groups, dsh=args.dsh, plotdir=args.plotdir,
         start_ts=start_ts, end_ts=end_ts, tz=tz, nodes=args.node,
         csv_name_to_path=csv_name_to_path)
