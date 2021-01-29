#!/bin/bash

vault secrets enable gcp

# 1. Generated a service account json file from GCP console
# The service principal credentials for vault in our GCP account are stored as
# a vault secret

vault kv get -field=data secret/gcp/vaultsp | vault write gcp/config credentials=-

# 2. Create a 'roleset', literally a set of roles. These are in the format below,
# specified as a bunch of scopes (eg, entire project, particular service, etc)
# and a set of resources with roles for them. This token scope generated OAuth2
# tokens

vault write gcp/roleset/my-token-roleset \
    project="angular-expanse-99923" \
    secret_type="access_token"  \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/angular-expanse-99923" {
roles = ["roles/viewer"]
}
EOF

# You can also generate Google Service Accounts. Too powerful and not as flexible as
# OAuth2

vault write gcp/roleset/my-sa-roleset \
    project="angular-expanse-99923" \
    secret_type="service_account_key"  \
    bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/angular-expanse-99923" {
roles = ["roles/viewer"]
}
EOF

vault write gcp/roleset/gcsadmin \
    project="angular-expanse-99923" \
    secret_type="service_account_key"  \
    bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/angular-expanse-99923" {
roles = ["roles/storage.objectAdmin"]
}
EOF

# Now we have this my-token-roleset, we can generate credentials for it
vault read gcp/token/gcsadmin



# Now we have this my-token-roleset, we can generate credentials for it
vault read gcp/token/my-token-roleset

#Key                   Value
#---                   -----
#expires_at_seconds    1543185643
#token                 ya29.c.ElpfBtN2fwwyFseDTUx1Hki0_dF4F3aLY-GDK_K8bB1D6Ktf_gmCceQTPq3EDszIXGxMhR1AsVhZLAnUWTIhZ81qlt1aOZDY4YFs6GQ_EB59XaSTc7sXmz2At7Y
#token_ttl             59m59s

# Use via `curl -H "Authorization: Bearer ya29.c.ElpfBtN2fww... "`
