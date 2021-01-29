FROM tiangolo/uwsgi-nginx-flask:python3.6

MAINTAINER Devang Shah <dshah@xcalar.com>

# Context is set to xcalar-infra/ by dbuild
COPY ubm_perf/grafana/requirements.txt /app
RUN pip install --no-cache-dir -r requirements.txt

# Environment configuration override as needed...
ENV LOG_LEVEL=INFO
ENV JENKINS_HOST=jenkins.int.xcalar.com

# Flask app needs to be in main.py for NGINX container
COPY ubm_perf/grafana/ubm_perf_datasource.py /app/main.py

RUN mkdir -p /app/ubm_perf
COPY ubm_perf /app/ubm_perf/

RUN mkdir -p /app/py_common
COPY py_common /app/py_common/
