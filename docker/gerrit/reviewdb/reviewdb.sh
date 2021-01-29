#!/bin/bash

sed -i -e '/listen_address/d' $PGDATA/postgresql.conf
echo "listen_addresses = '*'" >> $PGDATA/postgresql.conf
exit 0

gerrit2="$(psql --username=postgres postgres -c '\du gerrit2' | grep gerrit2)"
if [ -z "$gerrit2" ]; then
    createuser --username=postgres -RDIElPS gerrit2
fi

reviewdb="$(psql --username=postgres postgres -c '\l reviewdb' | grep reviewdb)"
if [ -z "$reviewdb" ]; then
    createdb --username=postgres -E UTF-8 -O gerrit2 reviewdb
fi

