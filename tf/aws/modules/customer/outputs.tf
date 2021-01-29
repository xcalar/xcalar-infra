#output "database_subnets" {
#  value = ["${aws_subnet.database.*.id}"]
#}

output "bucket" {
    value = "{aws_s3_bucket.mod.id}"
}

output "access_key_id" {
    value = "{aws_iam_access_key.mod.id}"
}

output "secret_access_key" {
    value = "{aws_iam_access_key.mod.secret}"
}


