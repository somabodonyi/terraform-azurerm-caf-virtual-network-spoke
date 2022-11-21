#---------------------------------
# Local declarations
#---------------------------------
locals {
  resource_group_name    = element(coalescelist(data.azurerm_resource_group.rgrp.*.name, azurerm_resource_group.rg.*.name, [""]), 0)
  location               = element(coalescelist(data.azurerm_resource_group.rgrp.*.location, azurerm_resource_group.rg.*.location, [""]), 0)
  netwatcher_rg_name     = element(coalescelist(data.azurerm_resource_group.netwatch.*.name, azurerm_resource_group.nwatcher.*.name, [""]), 0)
  netwatcher_rg_location = element(coalescelist(data.azurerm_resource_group.netwatch.*.location, azurerm_resource_group.nwatcher.*.location, [""]), 0)
  if_ddos_enabled        = var.create_ddos_plan ? [{}] : [] 
  }


#---------------------------------------------------------
# Resource Group Creation or selection - Default is "true"
#----------------------------------------------------------
data "azurerm_resource_group" "rgrp" {
  count = var.create_resource_group == false ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group ? 1 : 0
  name     = lower(var.resource_group_name)
  location = var.location
  tags     = var.tags
}

#-------------------------------------
# VNET Creation - Default is "true"
#-------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = lower(var.spoke_vnet_name)
  location            = local.location
  resource_group_name = local.resource_group_name
  address_space       = var.vnet_address_space
  dns_servers         = var.dns_servers
  tags                = var.tags

  dynamic "ddos_protection_plan" {
    for_each = local.if_ddos_enabled

    content {
      id     = azurerm_network_ddos_protection_plan.ddos[0].id
      enable = true
    }
  }
}

#--------------------------------------------
# Ddos protection plan - Default is "false"
#--------------------------------------------
resource "azurerm_network_ddos_protection_plan" "ddos" {
  count               = var.create_ddos_plan ? 1 : 0
  name                = lower("${var.spoke_vnet_name}-ddos-protection-plan")
  resource_group_name = local.resource_group_name
  location            = local.location
  tags                = var.tags
}

#-------------------------------------
# Network Watcher - Default is "true"
#-------------------------------------
data "azurerm_resource_group" "netwatch" {
  count = var.is_spoke_deployed_to_same_hub_subscription == true ? 1 : 0
  name  = "NetworkWatcherRG"
}

resource "azurerm_resource_group" "nwatcher" {
  count    = var.is_spoke_deployed_to_same_hub_subscription == false ? 1 : 0
  name     = "NetworkWatcherRG"
  location = local.location
  tags     = var.tags
}

resource "azurerm_network_watcher" "nwatcher" {
  count               = var.is_spoke_deployed_to_same_hub_subscription == false ? 1 : 0
  name                = "NetworkWatcher_${local.location}"
  location            = local.netwatcher_rg_location
  resource_group_name = local.netwatcher_rg_name
  tags                = var.tags
}

#--------------------------------------------------------------------------------------------------------
# Subnets Creation with, private link endpoint/servie network policies, service endpoints and Deligation.
#--------------------------------------------------------------------------------------------------------
resource "azurerm_subnet" "snet" {
  for_each             = var.subnets
  name                 = lower(each.value.subnet_name)
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.subnet_address_prefix
  service_endpoints    = lookup(each.value, "service_endpoints", [])
  # Applicable to the subnets which used for Private link endpoints or services 
  private_endpoint_network_policies_enabled     = lookup(each.value, "private_endpoint_network_policies_enabled", null)
  private_link_service_network_policies_enabled = lookup(each.value, "private_link_service_network_policies_enabled", null)

  dynamic "delegation" {
    for_each = lookup(each.value, "delegation", {}) != {} ? [1] : []
    content {
      name = lookup(each.value.delegation, "name", null)
      service_delegation {
        name    = lookup(each.value.delegation.service_delegation, "name", null)
        actions = lookup(each.value.delegation.service_delegation, "actions", null)
      }
    }
  }
}


resource "azurerm_route_table" "rtout" {
  name                = var.route_table_name
  location            = local.location
  resource_group_name = local.resource_group_name
  dynamic "route" {
    for_each = var.routes
    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }
  disable_bgp_route_propagation = var.disable_bgp_route_propagation
  tags                          = var.tags
}

resource "azurerm_subnet_route_table_association" "rtassoc" {
  for_each       = var.subnets
  subnet_id      = azurerm_subnet.snet[each.key].id
  route_table_id = azurerm_route_table.rtout.id
}





#---------------------------------------------
# Linking Spoke Vnet to Hub Private DNS Zone
#---------------------------------------------
resource "azurerm_private_dns_zone_virtual_network_link" "dzvlink" {
  provider              = azurerm.hub
  for_each               = var.private_dns_zone_registration ? var.private_dns_zone_names : {}
  name                  = lower("vnl-${azurerm_virtual_network.vnet.name}")
  resource_group_name   = var.private_dns_zone_resource_group_name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  private_dns_zone_name = each.value
  registration_enabled  = false
  tags                  = var.tags
}

#-----------------------------------------------
# Peering between Hub and Spoke Virtual Network
#-----------------------------------------------
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = lower("peering-to-${element(split("/", var.hub_virtual_network_id), 8)}")
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = var.hub_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider                     = azurerm.hub
  name                         = lower("peering-${element(split("/", var.hub_virtual_network_id), 8)}-to-${var.spoke_vnet_name}")
  resource_group_name          = element(split("/", var.hub_virtual_network_id), 4)
  virtual_network_name         = element(split("/", var.hub_virtual_network_id), 8)
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_gateway_transit        = true
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

#-----------------------------------------
# Network flow logs for subnet and NSG
#-----------------------------------------
/* resource "azurerm_network_watcher_flow_log" "nwflog" {
  for_each                  = var.subnets
  network_watcher_name      = var.is_spoke_deployed_to_same_hub_subscription == true ? "NetworkWatcher_${local.netwatcher_rg_location}" : azurerm_network_watcher.nwatcher.0.name
  resource_group_name       = local.netwatcher_rg_name # Must provide Netwatcher resource Group
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
  storage_account_id        = var.hub_storage_account_id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = 0
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = var.log_analytics_customer_id
    workspace_region      = local.location
    workspace_resource_id = var.log_analytics_workspace_id
    interval_in_minutes   = 10
  }
} */

/* #---------------------------------------------------------------
# azurerm monitoring  - VNet, NSG, PIP, and Firewall
#---------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = lower("vnet-${var.spoke_vnet_name}-diag")
  target_resource_id         = azurerm_virtual_network.vnet.id
  storage_account_id         = var.hub_storage_account_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "VMProtectionAlerts"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
} */

/* resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each                   = var.subnets
  name                       = lower("${each.key}-diag")
  target_resource_id         = azurerm_network_security_group.nsg[each.key].id
  storage_account_id         = var.hub_storage_account_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "log" {
    for_each = var.nsg_diag_logs
    content {
      category = log.value
      enabled  = true

      retention_policy {
        enabled = false
      }
    }
  }
} */

#---------------------------------------------------------------
# NAT Gateway
#---------------------------------------------------------------
resource "azurerm_public_ip" "pip" {
  count               = var.create_nat_gateway ? 1 : 0
  allocation_method   = "Static"
  location            = local.location
  name                = var.public_ip_name
  resource_group_name = local.resource_group_name
  sku                 = "Standard"


  tags = var.tags
}

resource "azurerm_nat_gateway" "natgw" {
  count                   = var.create_nat_gateway ? 1 : 0
  location                = local.location
  name                    = var.nat_gateway_name
  resource_group_name     = local.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "pip_assoc" {
  count                = var.create_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.natgw[count.index].id
  public_ip_address_id = azurerm_public_ip.pip[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "subnet_assoc" {
  #for_each       = azurerm_subnet.snet 
  for_each = tomap({
    for k, subnets in azurerm_subnet.snet : k => subnets.id if var.create_nat_gateway && length(subnets.delegation) != 0 ? subnets.delegation[0].service_delegation[0].name == "Microsoft.Web/serverFarms" : false
  })
  nat_gateway_id = azurerm_nat_gateway.natgw[0].id
  subnet_id      = each.value
  depends_on = [
    azurerm_subnet.snet
  ]
}
