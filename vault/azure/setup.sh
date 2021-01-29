#!/bin/bash

set -eu

# 'subscription' needs to be set seperately, it isn't stored with any of the datastructures. Easy
# enough with someone who can run `az account list`.

# Grab the AzureSP from Vault. This was pregenerated offline and stored as a json object that this path
# The SP gives Owner permission to the subscription and 2 very powerful Read/Write caps to AAD, since
# it needs to be able to generate SPs on the fly
eval $(vault kv get -field=data -format=yaml secret/azure/VaultSecrets | sed 's/: /=/g')
subscription=$(az account show -ojson --query id -otsv)

vault write azure/config \
    subscription_id=$subscription \
    tenant_id=$tenant  \
    client_id=$appId \
    client_secret="$password"

# With the SP account above we define a role in the given subscription to have 'Contributor'
# access to all resourceGroups. Basically "root" for all intents and purposes.
vault write azure/roles/developer ttl=6h max_ttl=24h azure_roles=-<<EOF
[
  {
    "role_id": "/subscriptions/${subscription}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
    "scope": "/subscriptions/${subscription}"
  }
]
EOF

# A more limited role. One that is limited to the xcalarDev-rg resourceGroup
vault write azure/roles/xcalardev ttl=6h max_ttl=24h azure_roles=-<<EOF
[
  {
    "role_id": "/subscriptions/${subscription}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
    "scope": "/subscriptions/${subscription}/resourceGroups/xcalarDev-rg"
  }
]
EOF

cat >&2 << EOF
Finished!!

Now yo can generate temporary Azure SP credentials via :

  vault read azure/creds/developer ttl=900

  vault read azure/creds/xcalardev ttl=3600

EOF
