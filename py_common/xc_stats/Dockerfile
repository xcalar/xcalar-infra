FROM python:3.6

MAINTAINER Robert Stephens <rstephens@xcalar.com>

ENV MPLCONFIGDIR="/app/tmp"

RUN mkdir -p /app/tmp
RUN chmod 777 /app/tmp

WORKDIR /app

# Context is set to xcalar-infra/ by dbuild
COPY py_common/xc_stats ./
RUN pip install --no-cache-dir -r requirements.txt

CMD ["./plot.py"]
