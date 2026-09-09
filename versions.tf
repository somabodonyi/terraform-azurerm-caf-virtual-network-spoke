terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 5.0.0, < 6.0.0"
      configuration_aliases = [azurerm.hub]
    }
  }
  required_version = ">= 1.9.5, < 2.0.0"
}
