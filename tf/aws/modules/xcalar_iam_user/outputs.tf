output "access_key_id" {
    value = "${aws_iam_access_key.u.id}"
}

output "secret_access_key" {
    value = "${aws_iam_access_key.u.secret}"
}

output "name" {
    value = "${var.name}"
}
