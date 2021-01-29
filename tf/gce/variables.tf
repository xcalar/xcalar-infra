variable "access_key" {}
variable "secret_key" {}
variable "key_name" {
    default = "xcalar-us-west-2"
}
variable "key_path" {
    default = "~/.ssh/xcalar-us-west-2.pem"
}
variable "instance_type" {
    default = "m3.2xlarge"
}

variable "ami" {
    #default = "ami-34aa2454"
    default = "ami-434ac323"
}

variable "region" {
    default = "us-east-1"
}

variable "url" {
	default = "https://download.jboss.org/wildfly/9.0.1.Final/wildfly-9.0.1.Final.zip"
}

variable "cluster_size" {
    default = 2
}

variable "gce_credentials" {}
variable "gce_project" {}
variable "gce_region" {
    default = "us-central1"
}
variable "gce_zone" {
    default = "us-central1-f"
}
