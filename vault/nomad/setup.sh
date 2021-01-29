#!/bin/bash
# via https://www.nomadproject.io/guides/operations/vault-integration/index.html

# Download the policy and token role
curl https://nomadproject.io/data/vault/nomad-server-policy.hcl -O -s -L
curl https://nomadproject.io/data/vault/nomad-cluster-role.json -O -s -L

# Write the policy to Vault
vault policy write nomad-server nomad-server-policy.hcl

# Create the token role with Vault
vault write /auth/token/roles/nomad-cluster @nomad-cluster-role.json

vault token create -policy nomad-server -period 72h -orphan

echo "Now copy this token to /etc/sysconfig/nomad on all nomad servers"
