# Azure Role Definitions

These are custom RBAC roles needed for various reasons. To initially define a new
RBAC definition, use `az role definition create --role-definition @role.json`.
Subsequent updates can be done via `az role definitions update --role-definition`.


## NetworkInterface Lister

`networkLister.json`: Used by Azure MSI to grant the VM permissions to find cluster
members. Similar to AWS EC2's ec2:DescribeInstances IAM.
