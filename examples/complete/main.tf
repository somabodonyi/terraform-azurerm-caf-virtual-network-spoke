terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
  required_version = ">= 1.9.5"
}

# Provider for the subscription the spoke is deployed into.
provider "azurerm" {
  subscription_id = var.spoke_subscription_id
  features {}

  # AzureRM v5 no longer registers Resource Providers by default. Register the
  # ones this module needs, or set `resource_provider_registrations = "legacy"`
  # to keep the v4 behaviour.
  resource_providers_to_register = ["Microsoft.Network"]
}

# Provider for the hub subscription. The module uses this to create the
# hub-to-spoke peering and the Private DNS zone virtual network links.
provider "azurerm" {
  alias           = "hub"
  subscription_id = var.hub_subscription_id
  features {}

  resource_providers_to_register = ["Microsoft.Network"]
}

data "azurerm_virtual_network" "hub" {
  provider            = azurerm.hub
  name                = var.hub_virtual_network_name
  resource_group_name = var.hub_resource_group_name
}

module "vnet-spoke" {
  source = "../../"

  providers = {
    azurerm.hub = azurerm.hub
  }

  # By default, this module will create a resource group. To use an existing
  # resource group, specify the existing resource group name and set
  # `create_resource_group = false`. Location will be the same as the existing RG.
  create_resource_group = true
  resource_group_name   = "rg-spoke-demo-internal-shared-westeurope-001"
  location              = "westeurope"
  spoke_vnet_name       = "default-spoke"

  # Set to false when the spoke is deployed to a different subscription than the
  # hub, so that this module manages the NetworkWatcherRG / Network Watcher.
  is_spoke_deployed_to_same_hub_subscription = var.hub_subscription_id == var.spoke_subscription_id

  # Provide a valid VNet address space for the spoke virtual network.
  vnet_address_space = ["10.2.0.0/16"]

  # Hub network details, used to create the peerings in both directions.
  hub_virtual_network_id          = data.azurerm_virtual_network.hub.id
  hub_firewall_private_ip_address = "10.1.0.4"

  # Register the spoke VNet against the Private DNS zones hosted in the hub.
  # Set `private_dns_zone_registration = false` to skip this entirely.
  private_dns_zone_registration        = true
  private_dns_zone_resource_group_name = var.private_dns_zone_resource_group_name
  private_dns_zone_names = {
    privatelink_blob_core_windows_net = "privatelink.blob.core.windows.net",
    privatelink_database_windows_net  = "privatelink.database.windows.net",
  }

  # Multiple subnets, with optional service delegation and service endpoints.
  # The route table below is associated with every subnet listed here.
  subnets = {
    app_subnet = {
      subnet_name           = "application"
      subnet_address_prefix = ["10.2.1.0/24"]
      service_endpoints     = ["Microsoft.Storage"]
    }

    db_subnet = {
      subnet_name           = "database"
      subnet_address_prefix = ["10.2.2.0/24"]
      service_endpoints     = ["Microsoft.Storage", "Microsoft.Sql"]
    }

    # Subnets delegated to Microsoft.Web/serverFarms are automatically
    # associated with the NAT Gateway when `create_nat_gateway = true`.
    web_subnet = {
      subnet_name           = "webapps"
      subnet_address_prefix = ["10.2.3.0/24"]
      service_endpoints     = []
      delegation = {
        name = "delegation"
        service_delegation = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  }

  # Route table applied to all subnets above. Routes are optional.
  route_table_name = "rt-default-spoke"
  routes = [
    {
      name                   = "route-to-hub-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = "10.1.0.4"
    },
  ]

  # Outbound internet access for the delegated subnets.
  create_nat_gateway = true
  nat_gateway_name   = "ngw-default-spoke"
  public_ip_name     = "pip-ngw-default-spoke"

  # Adding TAGs to your Azure resources
  tags = {
    ProjectName  = "demo-internal"
    Env          = "dev"
    Owner        = "user@example.com"
    BusinessUnit = "CORP"
    ServiceClass = "Gold"
  }
}
