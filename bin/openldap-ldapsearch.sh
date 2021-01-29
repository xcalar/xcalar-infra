#!/bin/bash
ldapsearch -h ldap.int.xcalar.com -p 389 -D uid=bind,ou=Services,dc=int,dc=xcalar,dc=com -w 'welcome1' -b 'ou=People,dc=int,dc=xcalar,dc=com' -s sub '(&(objectclass=inetOrgPerson)(uid=*))'
