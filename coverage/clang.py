#!/usr/bin/env python3

# Copyright 2019-2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import gzip
import json
import logging
import os
import pprint
import re
import subprocess
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.env_configuration import EnvConfiguration
from py_common.jenkins_aggregators import JenkinsAggregatorBase
from py_common.mongo import MongoDB

class ClangExecutableNotFound(Exception):
    pass

class ClangCoverageFilenameCollision(Exception):
    pass

class ClangCoverageEmptyFile(Exception):
    pass

class ClangCoverageNoData(Exception):
    pass

class ClangCoverageNoBinary(Exception):
    pass

class ClangCoverageFile(object):

    GZIPPED = re.compile(r".*\.gz\Z")

    def __init__(self, *, path):
        self.logger = logging.getLogger(__name__)
        self.path = path
        self.coverage_data = self._load_json()

    def _load_json(self):
        path = self.path
        if not os.path.exists(path):
            # Try gzipped form
            zpath = "{}.gz".format(path)
            if not os.path.exists(zpath):
                err = "neither {} nor {} exist".format(path, zpath)
                self.logger.error(err)
                raise FileNotFoundError(err)
            path = zpath

        jstr = ""
        if self.GZIPPED.match(path):
            with gzip.open(path, "rb") as fh:
                jstr = fh.read().decode("utf-8")
        else:
            with open(path, "r") as fh:
                jstr = fh.read()

        if not len(jstr):
            raise ClangCoverageEmptyFile("{} is empty".format(path))
        return json.loads(jstr)

    def file_summaries(self):
        """
        Strip a full coverage results file down to just per-file summary data.
        Returns dictionary:
            {<file_path>: {<file_summary_data>},
             <file_path>: {<file_summary_data>},
             ...
             "totals": {<total_summary_data}}
        """
        summaries = {}
        if 'data' not in self.coverage_data:
            return summaries
        for info in self.coverage_data['data']:
            totals = info.get('totals', None)
            if totals:
                summaries['totals'] = totals
            for finfo in info['files']:
                filename = finfo.get('filename', None)
                if not filename:
                    continue # :|
                if filename in summaries:
                    raise ClangCoverageFilenameCollision(
                            "colliding file name: {}".format(filename))
                summaries[filename] = finfo.get('summary', None)
        return summaries


class ClangCoverageTools(object):

    # Containers may need to pass in explicit paths
    ENV_PARAMS = {"CLANG_LLVM_COV_PATH": {},
                  "CLANG_LLVM_PROFDATA_PATH": {}}

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        cfg = EnvConfiguration(ClangCoverageTools.ENV_PARAMS)

        # If explicit paths are passed, use those.
        self.llvm_cov_path = cfg.get("CLANG_LLVM_COV_PATH")
        self.llvm_profdata_path = cfg.get("CLANG_LLVM_PROFDATA_PATH")

        if self.llvm_cov_path is None or self.llvm_profdata_path is None:

            # If no explicit paths are given, find the "clang" binary.

            try:
                cargs = ["which", "clang"]
                cp = subprocess.run(cargs, stdout=subprocess.PIPE)
                clang_bin_path = cp.stdout.decode('utf-8').strip()
                if not clang_bin_path:
                    raise ClangExecutableNotFound("no clang path found")
                if not os.path.exists(clang_bin_path):
                    raise ClangExecutableNotFound("clang path {} does not exist"
                                                  .format(clang_bin_path))
            except Exception as e:
                raise

            # Assumption is that the llvm tools co-reside with the clang binary.

            self.clang_bin_dir = os.path.dirname(clang_bin_path)
            self.llvm_cov_path = os.path.join(clang_bin_dir, "llvm-cov")
            self.llvm_profdata_path = os.path.join(clang_bin_dir, "llvm-profdata")

        if not os.path.exists(self.llvm_cov_path):
            raise ClangExecutableNotFound("llvm-cov path {} does not exist"
                                          .format(self.llvm_cov_path))
        if not os.path.exists(self.llvm_profdata_path):
            raise ClangExecutableNotFound("llvm-profdata path {} does not exist"
                                          .format(self.llvm_profdata_path))


class ClangCoverageDir(object):

    ENV_PARAMS = {"CLANG_BIN_PATH": {"default":"/usr/local/bin/clang"},
                  "ARTIFACTS_RAWPROF_DIR_NAME": {"default": "rawprof"},
                  "ARTIFACTS_BIN_DIR_NAME": {"default": "bin"},
                  "ARTIFACTS_SRC_DIR_NAME": {"default": "src"}}

    def __init__(self, *, coverage_dir, bin_name="usrnode",
                                        profdata_file_name="usrnode.profdata",
                                        json_file_name="coverage.json"):


        cfg = EnvConfiguration(ClangCoverageDir.ENV_PARAMS)

        self.logger = logging.getLogger(__name__)
        self.coverage_dir = coverage_dir
        self.bin_name = bin_name
        self.profdata_file_name = profdata_file_name
        self.json_file_name = json_file_name
        self.rawprof_dir_name = cfg.get("ARTIFACTS_RAWPROF_DIR_NAME")
        self.bin_dir_name = cfg.get("ARTIFACTS_BIN_DIR_NAME")
        self.src_dir_name = cfg.get("ARTIFACTS_SRC_DIR_NAME")
        self.clang_bin_path = cfg.get("CLANG_BIN_PATH")

    def bin_path(self):
        return os.path.join(self.coverage_dir, self.bin_dir_name, self.bin_name)

    def src_dir_path(self):
        return os.path.join(self.coverage_dir, self.src_dir_name)

    def profdata_path(self):
        return os.path.join(self.coverage_dir, self.profdata_file_name)

    def json_path(self):
        return os.path.join(self.coverage_dir, self.json_file_name)

    def _create_profdata(self, *, clang_tools, work_dir, force):
        """
        work_dir is expected to have a "raw profile data" directory
        (named by ARTIFACTS_RAWPROF_DIR_NAME).

        Process the raw data and leave a profdata index file
        in the working directory (e.g. usrnode.profdata)
        """
        self.logger.debug("start work_dir {} force {}".format(work_dir, force))
        profdata_path = os.path.join(work_dir, self.profdata_file_name)
        self.logger.debug("profdata_path: {}".format(profdata_path))
        if os.path.exists(profdata_path) and not force:
            self.logger.info("{} exists and not force, skipping...".format(profdata_path))
            return [profdata_path]

        rawprof_dir = os.path.join(work_dir, self.rawprof_dir_name)
        self.logger.debug("rawprof_dir: {}".format(rawprof_dir))
        if not os.path.exists(rawprof_dir):
            self.logger.debug("{} doesn't exist".format(rawprof_dir))
            file_list = []
            for name in os.listdir(work_dir):
                path = os.path.join(work_dir, name)
                if os.path.isdir(path):
                    file_list.extend(self._create_profdata(clang_tools=clang_tools,
                                                           work_dir=path,
                                                           force=force))
            return file_list

        self.logger.debug("{} exists".format(rawprof_dir))

        merge_files_path = os.path.join(work_dir, 'merge.files')
        tmp_profdata = os.path.join(work_dir, "tmp.profdata")

        # Some rawprof files will not merge due to what is reported as
        # header corruption.  This is likely incomplete files due to
        # some shutdown issue.  To get the maximum number of files merged
        # without having one bad apple kill the whole merge, merge files
        # one at a time and keep accumulating the merge results.
        if os.path.exists(profdata_path):
            os.remove(profdata_path)
        for fname in os.listdir(rawprof_dir):
            with open(merge_files_path, 'w+') as f:
                if os.path.exists(profdata_path):
                    # If we have a merge result, off-name and merge the
                    # next file into it.
                    self.logger.debug("{} exists, rename to {}"
                                      .format(profdata_path, tmp_profdata))
                    os.rename(profdata_path, tmp_profdata)
                    self.logger.debug("merging {}...".format(tmp_profdata))
                    f.write("{}\n".format(tmp_profdata))

                raw_path = os.path.join(rawprof_dir, fname)
                self.logger.debug("merging {}...".format(raw_path))
                f.write("{}\n".format(raw_path))

            cargs = [clang_tools.llvm_profdata_path, "merge"]
            cargs.extend(["-f", merge_files_path])
            cargs.extend(["-o", profdata_path])
            self.logger.debug("run: {}".format(cargs))
            cp = subprocess.run(cargs,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
            if not cp.returncode:
                self.logger.debug("success...")
                continue

            self.logger.debug("fail...")
            if os.path.exists(tmp_profdata):
                # On merge failure, reset by restoring the profdata file
                # we off-named above, and start the next cycle.
                self.logger.debug("{} exists, rename to {}"
                                  .format(tmp_profdata, profdata_path))
                os.rename(tmp_profdata, profdata_path)

        if os.path.exists(tmp_profdata):
            # Clean up any "intermediary" file.
            os.remove(tmp_profdata)

        return [profdata_path]



    @classmethod
    def _create_json(cls, *, clang_tools, out_dir, bin_path, profdata_path, force):
        logger = logging.getLogger(__name__)
        logger.debug("start")

        json_file_path = os.path.join(out_dir, 'coverage.json')
        if os.path.exists(json_file_path) and not force:
            logger.info("{} exists and not force, skipping...".format(json_file_path))
            return

        cargs = [clang_tools.llvm_cov_path, "export", bin_path]
        cargs.extend(["-instr-profile", profdata_path])
        cargs.extend(["-format", "text"])
        logger.debug("run: {}".format(cargs))
        with open(json_file_path, "w+") as fd:
            cp = subprocess.run(cargs, stdout=fd, stderr=subprocess.PIPE)
            if cp.returncode:
                raise Exception("llvm-cov failure while creating coverage.json\n{}"
                                .format(cp.stderr.decode('utf-8')))

    @classmethod
    def _create_html(cls, *, clang_tools, out_dir, src_dir, bin_path, profdata_path, force):
        logger = logging.getLogger(__name__)
        logger.debug("start")

        html_path = os.path.join(out_dir, "index.html")
        if os.path.exists(html_path) and not force:
            logger.info("{} exists and not force, skipping...".format(html_path))
            return

        cargs = [clang_tools.llvm_cov_path, "show", bin_path]
        cargs.extend(["-instr-profile", profdata_path])
        cargs.extend(["-format", "html"])
        cargs.extend(["-output-dir", out_dir])
        if src_dir is not None and os.path.exists(src_dir):
            cargs.extend(["--path-equivalence", "/,{}".format(src_dir)])
        else:
            logger.error("expected src dir {} does not exist".format(src_dir))
        logger.debug("run: {}".format(cargs))
        cp = subprocess.run(cargs, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if cp.returncode:
            err = "llvm-cov failure: {}".format(cp.stdout.decode('utf-8'))
            raise Exception(err)

        coverage_dir_path = os.path.join(out_dir, "coverage")
        if os.path.exists(coverage_dir_path):
            cargs = ["chmod", "-R", "o+rx", coverage_dir_path]
            cp = subprocess.run(cargs, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if cp.returncode:
                err = "chmod failure: {}".format(cp.stdout.decode('utf-8'))
                logger.error(err)

    @classmethod
    def _merge_profdata(cls, *, clang_tools, profdata_files, profdata_path, force):
        """
        Merge profdata files
        """
        logger = logging.getLogger(__name__)

        if os.path.exists(profdata_path) and not force:
            logger.info("{} exists and not force, skipping...".format(profdata_path))
            return

        cargs = [clang_tools.llvm_profdata_path, "merge"]
        for path in profdata_files:
            cargs.append(path)
        cargs.extend(["-o", profdata_path])
        logger.debug("run command: {}".format(cargs))
        cp = subprocess.run(cargs,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
        if cp.returncode:
            raise Exception("llvm-profdata failure creating merged index\n{}"
                            .format(cp.stdout.decode('utf-8')))

    def process(self, *, force=False, create_json=True, create_html=True):
        """
        Process coverage data in our directory.
        """
        clang_tools = ClangCoverageTools()

        bin_path = self.bin_path()
        if not os.path.exists(bin_path):
            raise ClangCoverageNoBinary("{} does not exist".format(bin_path))

        profdata_files = self._create_profdata(clang_tools=clang_tools,
                                               work_dir=self.coverage_dir,
                                               force=force)
        self.logger.debug("profdata_files: {}".format(profdata_files))
        if not profdata_files:
            raise ClangCoverageNoData("No valid rawprof files found")

        profdata_path = os.path.join(self.coverage_dir, self.profdata_file_name)

        if len(profdata_files) > 1:
            # Merge all sub-profdata...
            ClangCoverageDir._merge_profdata(clang_tools=clang_tools,
                                             profdata_files=profdata_files,
                                             profdata_path=profdata_path,
                                             force=force)
        else:
            assert(profdata_files[0] == profdata_path)

        self.logger.debug("final instr-profile file: {}".format(profdata_path))

        # coverage.json
        if create_json:
            self._create_json(clang_tools=clang_tools,
                              out_dir=self.coverage_dir,
                              bin_path=bin_path,
                              profdata_path=profdata_path,
                              force=force)

        # HTML
        if create_html:
            self._create_html(clang_tools=clang_tools,
                              out_dir=self.coverage_dir,
                              src_dir=self.src_dir_path(),
                              bin_path=bin_path,
                              profdata_path=profdata_path,
                              force=force)

    @classmethod
    def merge(cls, *, dirs,
                      out_dir,
                      src_dir,
                      bin_name="usrnode",
                      profdata_file_name="usrnode.profdata",
                      force=False,
                      create_json=True,
                      create_html=True):
        """
        Merge coverage from multiple directories into specified
        output directory.
        """
        logger = logging.getLogger(__name__)
        clang_tools = ClangCoverageTools()

        if len(dirs) < 1:
            raise ValueError("dirs list must contain at least one path")

        profdata_files = []
        bin_path = None
        for path in dirs:
            logger.debug("processing {}".format(path))
            cdir = cls(coverage_dir=path,
                       bin_name=bin_name,
                       profdata_file_name=profdata_file_name)
            cdir.process(force=force,
                         create_json=create_json,
                         create_html=create_html)
            # First binary encountered will be used for the final merge...
            if not bin_path:
                bin_path = cdir.bin_path()
            profdata_files.append(cdir.profdata_path())

        if not bin_path:
            raise ClangCoverageNoBinary("no bin_path returned")

        if not profdata_files:
            raise ClangCoverageNoData("No profdata files found")

        profdata_path = os.path.join(out_dir, profdata_file_name)

        cls._merge_profdata(clang_tools=clang_tools,
                            profdata_files=profdata_files,
                            profdata_path=profdata_path,
                            force=True) # Always re-create output files
        # coverage.json
        if create_json:
            cls._create_json(clang_tools=clang_tools,
                             out_dir=out_dir,
                             bin_path=bin_path,
                             profdata_path=profdata_path,
                             force=True) # Always re-create output files

        # HTML
        if create_html:
            cls._create_html(clang_tools=clang_tools,
                             out_dir=out_dir,
                             src_dir=src_dir,
                             bin_path=bin_path,
                             profdata_path=profdata_path,
                             force=True) # Always re-create output files

    def _do_diff(self, *, new, base):
        self.logger.debug("BASE: {}".format(base))
        self.logger.debug("THIS: {}".format(new))
        diff = {}
        if new['count'] != base['count']:
            raise Exception("count mismatch")
        diff['count'] = new['count']
        diff['covered'] = new['covered'] - base['covered']
        if diff['count'] == 0:
            diff['percent'] = 0
        else:
            diff['percent'] = (diff['covered']*100)/diff['count']
        self.logger.debug("DIFF: {}".format(diff))
        return diff


    def diff(self, *, base_dir):
        summaries_base = ClangCoverageFile(path=base_dir.json_path()).file_summaries()
        summaries_new = ClangCoverageFile(path=self.json_path()).file_summaries()
        only_base = {}
        only_new = {}
        diffs = {}
        # This minus base
        for key in summaries_base.keys():
            if key not in summaries_new:
                only_base[key] = base[key]
        for key in summaries_new.keys():
            if key not in summaries_base:
                only_new[key] = new[key]
            diffs[key] = {}
            for section in ['lines', 'functions', 'instantiations', 'regions']:
                diffs[key][section] = self._do_diff(new = summaries_new[key][section],
                                                    base = summaries_base[key][section])
        return {'diffs': diffs,
                'only_base': only_base,
                'only_new': only_new}

class ClangCoverageAggregator(JenkinsAggregatorBase):

    def __init__(self, *, job_name,
                          agg_name,
                          coverage_file_name,
                          artifacts_root):

        self.logger = logging.getLogger(__name__)
        self.coverage_file_name = coverage_file_name
        self.artifacts_root = artifacts_root
        super().__init__(job_name=job_name, agg_name=agg_name)

    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):

        bnum = jbi.build_number
        dir_path = os.path.join(self.artifacts_root, bnum)
        coverage_dir = ClangCoverageDir(coverage_dir=dir_path)
        try:
            coverage_dir.process()
        except:
            self.logger.exception("exception processing: {}".format(dir_path))

        """
        Read the coverage.json file and convert to our preferred index form,
        filtering for only files of interest (plus totals).
        """
        coverage_file_path = os.path.join(self.artifacts_root, bnum, self.coverage_file_name)
        try:
            summaries = ClangCoverageFile(path=coverage_file_path).file_summaries()
        except FileNotFoundError:
            self.logger.exception("file not found: {}".format(coverage_file_path))
            return None
        except ClangCoverageEmptyFile:
            self.logger.exception("file is empty: {}".format(coverage_file_path))
            return None
        except Exception:
            self.logger.exception("exception loading: {}".format(coverage_file_path))
            raise

        data = {}
        for filename, summary in summaries.items():
            data.setdefault('coverage', {})[MongoDB.encode_key(filename)] = summary
        return data


if __name__ == '__main__':
    cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.DEBUG}})
    logging.basicConfig(level=cfg.get("LOG_LEVEL"),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)
    print("Compile check A-OK!")
