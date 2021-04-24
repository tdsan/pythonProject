# Terraform script

provider "azurerm" {
  features{}
}

resource "azurerm_resource_group" "rg" {
  name      = var.info.name
  location  = var.info.location
}