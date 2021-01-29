FROM python:3.6

MAINTAINER Robert Stephens <rstephens@xcalar.com>

# Environment configuration override as needed...
ENV LOG_LEVEL="INFO"
ENV JENKINS_HOST="jenkins.int.xcalar.com"

# clang7 tools staged at /netstore/qa/coverage/clang7
# We use clang7 here in preference to infra-ubiquitous clang5 because
# clang5 merge is buggy (can't handle more than 3 data sets)
# and the reported coverage percentages seem inaccurate (see ENG-8898).
ENV CLANG_LLVM_COV_PATH="/netstore/qa/coverage/clang7/bin/llvm-cov"
ENV CLANG_LLVM_PROFDATA_PATH="/netstore/qa/coverage/clang7/bin/llvm-profdata"

# Tell the stats_plotter aggregator where to find the plotter utility
# and what to plot
ENV PLOTTER_PATH="/usr/src/app/py_common/xc_stats/plot.py"
ENV DEFAULT_PLOT_CFG_PATH="/usr/src/app/py_common/xc_stats/cfg/cpu_mem_pag_net.json"

WORKDIR /usr/src/app

# Context is set to xcalar-infra/ by dbuild
COPY py_common/jenkins_aggregators/update/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

RUN mkdir -p ./sql_perf
COPY sql_perf ./sql_perf/

RUN mkdir -p ./ubm_perf
COPY ubm_perf ./ubm_perf/

RUN mkdir -p ./coverage
COPY coverage ./coverage/

RUN mkdir -p ./py_common
COPY py_common ./py_common/

CMD ["./py_common/jenkins_aggregators/update/update.py"]
