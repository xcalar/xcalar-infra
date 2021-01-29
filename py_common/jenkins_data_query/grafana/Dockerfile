FROM tiangolo/uwsgi-nginx-flask:python3.6

MAINTAINER Robert Stephens <rstephens@xcalar.com>

# Environment configuration override as needed...
ENV LOG_LEVEL="INFO"
#ENV JDQ_SERVICE_HOST="jdq-back.service.consul"
ENV JDQ_SERVICE_HOST="cvraman3.int.xcalar.com"
#ENV JDQ_SERVICE_PORT="9999"
ENV JDQ_SERVICE_PORT="4000"

# Context is set to xcalar-infra/ by dbuild

COPY py_common/jenkins_data_query/grafana/requirements.txt /app
RUN pip install --no-cache-dir -r requirements.txt

# Flask app needs to be in main.py for NGINX container
COPY py_common/jenkins_data_query/grafana/main.py /app/main.py

RUN mkdir -p /app/py_common
COPY py_common /app/py_common/
