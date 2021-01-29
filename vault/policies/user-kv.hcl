# Allow ldap users to store secrets under user-kv/<username>/<key>

# Grant permissions on user specific path
path "user-kv/data/{{identity.entity.aliases.auth_ldap_10bd3898.name}}/*" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

# For Web UI usage
path "user-kv/metadata" {
  capabilities = ["list"]
}
