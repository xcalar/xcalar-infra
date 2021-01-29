path "secret/data/roles/jenkins-slave/*" {
  capabilities = ["read"]
}

path "secret/data/infra/vsphere-graphite" {
  capabilities = ["read"]
}

path "secret/data/infra/vsphere-prom" {
  capabilities = ["read"]
}

path "secret/data/infra/*" {
  capabilities = ["read"]
}

path "aws-xcalar/sts/*" {
  capabilities = ["update"]
}

path "secret/data/azblob/*" {
  capabilities = ["read", "list"]
}

path "secret/data/service_accounts/*" {
  capabilities = ["read", "list"]
}
