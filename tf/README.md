## Terraform: Initial checkin from early 2017 experiments

Decided not to go this route for general dev/prod workflow, but
it is still useful for one-off stuff like creating customer buckets
or users.

Very minimal documentation:

```
cd aws/customer
terraform init
make plan
```

Please talk to me first before doing a `terraform apply`! You will delete
the existing resources. This is one of the resons we didn't go for using
terraform. To do it properly you either need just one person/jenkins job
doing the `apply`, or you need to use a remote state which only works
properly in the paid version of terraform.

Please see [terraform documentation online](https://www.terraform.io/docs)

