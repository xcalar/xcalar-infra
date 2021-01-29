module "nogievetsky" {
    source = "../modules/xcalar_user"
    name = "nogievetsky"
}

resource "aws_s3_bucket" "restic" {
  bucket = "xcrestic"
  acl    = "private"

  tags {
    Name        = "Restic Backup"
    Environment = "Infra"
  }
}

resource "aws_iam_group" "restic_group" {
    name = "restic"
}

resource "aws_iam_group_policy" "restic_s3" {
    name = "xcalar-s3-${aws_s3_bucket.restic.bucket}-full-control"
    group = "${aws_iam_group.restic_group.id}"

    policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                    "s3:*"
                ],
                "Effect": "Allow",
                "Resource": [
                    "${aws_s3_bucket.restic.arn}/*",
                    "${aws_s3_bucket.restic.arn}"
                ]
            }
        ]
    }
EOF
}

module "restic_user" {
    source = "../modules/xcalar_iam_user"
    name = "restic"
    group = "${aws_iam_group.restic_group.name}"
}
