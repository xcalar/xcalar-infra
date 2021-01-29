#!/bin/bash

NAME="[$0]:"
DIR=$(dirname "${BASH_SOURCE[0]}")

ORIG_DIR=$(pwd)

_V=""

function exc () {
    if [[ $_V -eq 1 ]]; then
        "$@"
    else
        "$@" &> /dev/null
    fi
}

function log () {
    echo "$NAME $1"
}

if [ "$1" = "-v" -o "$1" = "--verbose" ]; then
    log "Executing in verbose mode"
    _V="1"
else
    log "Executing in non-verbose mode, run with -v for verbose"
fi

log "Moving to $DIR"
cd "$DIR"
sudo service mysql start || true

antiRequesites="libodbc1 unixodbc"
log "Cleaning up anti-requesites: $antiRequesites"
exc sudo apt-get -yqq remove "$antiRequesites"

log "Installing MySql"
exc sudo apt-get -yqq install mysql-server mysql-client

log "Installing MySql driver for testing"
exc sudo apt-get -yqq install libmyodbc

log "Installing unixodbc-bin"
exc sudo apt-get -yqq install unixodbc-bin unixodbc-dev

# get mySql .so files
mySFile=$(find /usr/lib -name '*libodbcmyS.so')
myOdbcFile=$(find /usr/lib -name '*libmyodbc.so')

driverFile="/etc/odbcinst.ini"
dsnFile="/etc/odbc.ini"

driverName="myodbc_mysql"
dsnName="MySql_Test"

databaseName="odbcTest"

grep -vq $driverName $driverFile
ret=$?

if [ $ret != "0" ]; then
    log "Adding $driverName to $driverFile"
    cat <<EOF | sudo tee -a $driverFile
[$driverName]
Description     = MySql ODBC driver
Driver          = $myOdbcFile
Setup           = $mySFile
UsageCount      = 1
EOF
else
    log "$driverFile already contains $driverName"
fi

log "Check if MySql requires a password"
mysql -uroot -e "help" 2>&1 | grep -q "Access denied"
requiresPassword=$?
if [ "$requiresPassword" != "0" ]; then
    password=""
else
    echo -n "Enter password: "
    read -s password
    echo
fi

mySqlSocket=$(mysqladmin -u root --password="$password" version | \
             grep -v "Connection" | \
             grep "UNIX socket" | \
             grep -o "/.*")

log "MySqlSocket is $mySqlSocket"

if ! grep -q $driverName $dsnFile ; then
    log "Adding $dsnName to $dsnFile"
    cat <<EOF | sudo tee -a $dsnFile
[$dsnName]
Description = This Data Source is for testing MySql ODBC
Driver      = $driverName
Server      = localhost
Username    = root
Password    = $password
Port        = 3306
Socket      = $mySqlSocket
Database    = $databaseName
Option      = 3
ReadOnly    = No
EOF
else
    log "$dsnFile already contains $driverName"
fi

log "Configuring odbcinst"
exc sudo odbcinst -i -d -f $driverFile

exc sudo odbcinst -i -s -l -f $dsnFile

log "Checking for $dsnName in the DSNs..."
odbcinst -s -q | grep -iq $dsnName
dsnPresent=$?
if [ $dsnPresent = "0" ]; then
    log "OK"
else
    log "DSN $dsnName not successfully added"
    cd "$ORIG_DIR"
    exit 1
fi

log "Checking for $driverName in the ODBC Drivers..."
odbcinst -d -q | grep -iq $driverName
driverPresent=$?
if [ $driverPresent = "0" ]; then
    log "OK"
else
    log "Driver $driverName not successfully added"
    cd "$ORIG_DIR"
    exit 1
fi

log "$dsnName and $driverName successfully installed"

log "Setting up MySql with $databaseName"

if [ "$requiresPassword" != "0" ]; then
    mysql -uroot -e "show databases;" | grep -q $databaseName
else
    mysql -uroot -p"$password" -e "show databases;" | grep -q $databaseName
fi
databasePresent=$?

if [ $databasePresent = "0" ]; then
    log "Database '$databaseName' already exists"
else
    log "Database '$databaseName' doesn't exist"
    if [ "$requiresPassword" != "0" ]; then
        exc mysql -uroot -e "create database $databaseName;"
    else
        exc mysql -uroot -p"$password" -e "create database $databaseName;"
    fi
    log "Database '$databaseName' created"
fi

echo "quit" | isql -v $dsnName "root" "$password"
ret=$?

if [ $ret = "0" ]; then
    log "isql was able to use the new ODBC driver"
    log "ODBC is now correctly installed on the machine"
else
    log "isql failed to connect"
    log "ODBC was not correctly installed; run uninstall or debug"
fi

log "Returning to $ORIG_DIR"
cd "$ORIG_DIR"
