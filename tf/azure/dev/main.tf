provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "dev" {
  name     = "xcalarDEV"
  location = "westus2"
}

module "network" {
  source              = "Azure/network/azurerm"
  resource_group_name = azurerm_resource_group.dev.name
  vnet_name           = "${azurerm_resource_group.dev.name}-vNET"
  location            = "westus2"
  address_space       = "10.0.0.0/16"
  subnet_prefixes     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  subnet_names        = ["infra_subnet", "subnet1", "abakshi-subnet", "blim-subnet"]

  #allow_ssh_traffic = true

  tags = {
    environment = "dev"
    costcenter  = "it"
    owner       = "autoeng"
  }
}

