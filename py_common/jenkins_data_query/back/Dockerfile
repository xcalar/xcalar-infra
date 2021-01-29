FROM tiangolo/uwsgi-nginx-flask:python3.6

MAINTAINER Robert Stephens <rstephens@xcalar.com>

# Environment configuration override as needed...
ENV LOG_LEVEL="ERROR"
ENV JENKINS_HOST="jenkins.int.xcalar.com"

# Context is set to xcalar-infra/ by dbuild

COPY py_common/jenkins_data_query/back/requirements.txt /app
RUN pip install --no-cache-dir -r requirements.txt

# Flask app needs to be in /app/main.py for NGINX container
COPY py_common/jenkins_data_query/back/main.py /app/main.py

RUN mkdir -p /app/py_common
COPY py_common /app/py_common/
