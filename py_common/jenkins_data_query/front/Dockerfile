FROM tiangolo/uwsgi-nginx-flask:python3.6

MAINTAINER Robert Stephens <rstephens@xcalar.com>

# Environment configuration override as needed...
ENV LOG_LEVEL="DEBUG"
ENV BACKEND_HOST="cvraman3.int.xcalar.com"
ENV BACKEND_PORT="4000"

# Context is set to xcalar-infra/ by dbuild

COPY py_common/jenkins_data_query/front/requirements.txt /app
RUN pip install --no-cache-dir -r requirements.txt

# Flask app needs to be in /app/main.py for NGINX container
COPY py_common/jenkins_data_query/front/main.py /app/main.py

RUN mkdir -p /app/templates
COPY py_common/jenkins_data_query/front/templates /app/templates/

RUN mkdir -p /app/py_common
COPY py_common /app/py_common/
