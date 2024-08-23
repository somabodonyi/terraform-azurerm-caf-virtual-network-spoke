terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
      configuration_aliases = [azurerm.hub]
    }
    random = {
      source = "hashicorp/random"
    }
  }
  required_version = ">= 1.9.5"
}
