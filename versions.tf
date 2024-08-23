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

provider "azurerm" {
  alias                           = "hub"
  resource_provider_registrations = "none"
  subscription_id                 = var.hub_subscription_id

  features {}
}
