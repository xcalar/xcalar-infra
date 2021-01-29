resource "aws_iam_user" "u" {
  name = "${var.name}"
  path = "/"
}

resource "aws_iam_user_login_profile" "u" {
	user = "${aws_iam_user.u.name}"
	pgp_key = "${var.pgp_key}"
}

#resource "aws_iam_group_membership" "mod" {
#  name = "${var.name}"
#
#  users = [
#    "${aws_iam_user.mod.name}"
#  ]
#
#  group = "${aws_iam_group.mod.name}"
#}

resource "aws_iam_access_key" "u" {
  user    = "${aws_iam_user.u.name}"
  pgp_key = "${var.pgp_key}"

}
