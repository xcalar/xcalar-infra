#!/bin/sh
/usr/sbin/kadmind -P /var/run/kadmind.pid
exec /usr/sbin/krb5kdc -P /var/run/krb5kdc.pid -n
