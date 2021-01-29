#!/bin/bash

DIG=($(dig redis.service.consul srv +short))

HOST=${DIG[3]}
PORT=${DIG[2]}

exec redis-cli -h $HOST -p $PORT "$@"
