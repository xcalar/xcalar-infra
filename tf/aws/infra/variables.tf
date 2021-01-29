variable "access_key" {}
variable "secret_key" {}
variable "key_name" {
    default = "xcalar-us-west-2"
}
variable "key_path" {
    default = "~/.ssh/xcalar-us-west-2.pem"
}
variable "instance_type" {
    default = "t2.medium"
}

# 2017-05-01T18:31:08  ami-20cf5740  simple  true  ubuntu-trusty-14.04-amd64-server-20170501_ixgbevf-4.0.3_ena-1.1.3-3ac3e0b
variable "ami" {
    default = "ami-e4ad3584"
    default = "ami-ab3cb5cb"
}

variable "region" {
    default = "us-west-2"
}

variable "account_id" {
    default = "559166403383"
}
