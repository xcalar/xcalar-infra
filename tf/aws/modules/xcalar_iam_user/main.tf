resource "aws_iam_user" "u" {
  name = "${var.name}"
  path = "/"
}

resource "aws_iam_group_membership" "u" {
  name = "${var.name}"

  users = [
    "${aws_iam_user.u.name}"
  ]

  group = "${var.group}"
}

resource "aws_iam_access_key" "u" {
  user    = "${aws_iam_user.u.name}"
  pgp_key = "${var.pgp_key}"

}
