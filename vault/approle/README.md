# Setup AppRole

    $ vault policy write jenkins_slave jenkins_slave.hcl
    $ vault write auth/approle/role/jenkins_slave token_policies=jenkins_slave token_ttl=6h token_max_ttl=48h
    #
    $ vault read auth/approle/role/jenkins_slave/role-id
    $ vault write -f auth/approle/role/jenkins_slave/secret-id
    # Use role_id and secret_id to login to vault
    $ vault write -format=json auth/approle/login role_id=xxxxx secret_id=yyyy
