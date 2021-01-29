# Vault Setup


## LDAP Auth

See [Vault LDAP](https://www.vaultproject.io/docs/auth/ldap.html)

Mount the LDAP auth backend

    $ vault write auth/ldap/config \
    url='ldap://ldap.int.xcalar.com:389' \
    userattr='uid' \
    userdn='ou=People,dc=int,dc=xcalar,dc=com' \
    groupdn='ou=Groups,dc=int,dc=xcalar,dc=com' \
    binddn='uid=bind,ou=Services,dc=int,dc=xcalar,dc=com' \
    bindpass='welcome1' \
    certificate=@ldap_ca_cert.pem insecure_tls=false starttls=true

And associate LDAP groups with policies

`
    $ vault write auth/ldap/groups/developers policies=developers
`
