terraform {
  backend "s3" {
    bucket = "xctfstate-us-east-1"
    key    = "tf/azure/dev/terraform.tfstate"
    region = "us-east-1"
  }
}

## Use the following to load remote state
#data "terraform_remote_state" "dev" {
#  backend = "s3"
#  config {
#    bucket = "xctfstate-us-east-1"
#    key    = "tf/azure/dev/terraform.tfstate"
#    region = "us-east-1"
#  }
#}
## Doesn't work at all without specifying a global SA key here??
#terraform {
#  backend "azurerm" {
#    storage_account_name = "xcalar"
#    container_name       = "tfstate"
#    key                  = "dev.terraform.tfstate"
#    access_key           = "STORAGE_KEY"
#  }
#}
