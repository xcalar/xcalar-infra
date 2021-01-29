#s3://xclogs/AWSLogs/559166403383/S3/

resource "aws_s3_bucket" "mod" {
  bucket = "${var.name}"
  acl    = "private"

  tags = "${var.tags}"
  logging {
    target_bucket = "xclogs"
    target_prefix = "AWSLogs/${var.account_id}/S3/${var.name}"
  }
}

resource "aws_iam_group" "mod" {
  name = "${var.name}"
}

resource "aws_iam_user" "mod" {
  name = "${var.name}"
  force_destroy = true
}

resource "aws_iam_group_membership" "mod" {
  name = "${var.name}"

  users = [
    "${aws_iam_user.mod.name}"
  ]

  group = "${aws_iam_group.mod.name}"
}

resource "aws_iam_access_key" "mod" {
  user    = "${aws_iam_user.mod.name}"
  pgp_key = "keybase:xcalar"

}

resource "aws_iam_group_policy" "s3_full_access" {
  name  = "${var.name}-s3-full-access"
  group = "${aws_iam_group.mod.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBuckets",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.mod.id}"
    },
    {
      "Sid": "AllowRWBucket",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${aws_s3_bucket.mod.id}/*"
    }
  ]
}
EOF

}
