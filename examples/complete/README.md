# Azure Virtual Network Spoke Terraform Module - Complete Example

This example deploys a spoke network using the [Microsoft recommended Hub-Spoke network topology](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke). Usually, only one hub in each region with multiple spokes and each of them can also be in separate subscriptions.

If you are deploying the spoke VNet in the same Hub Network subscription, then make sure you have set the argument `is_spoke_deployed_to_same_hub_subscription = true`. This helps the module manage the network watcher. If you are deploying the spoke VNets in separate subscriptions, set this argument to `false`.

This is designed to quickly deploy a hub and spoke architecture in Azure. Further security hardening, such as adding appropriate NSG rules, is recommended before using this for any production workloads.

## Requirements

Name | Version
-----|--------
terraform | >= 1.9.5
azurerm | >= 5.0.0, < 6.0.0

## Providers

This module declares `azurerm.hub` as a `configuration_aliases`, so the calling
configuration must define an aliased provider for the hub subscription and pass it in
through the `providers` argument. The module uses it for the hub-to-spoke peering and for
the Private DNS zone virtual network links.

```hcl
provider "azurerm" {
  subscription_id = var.spoke_subscription_id
  features {}

  # AzureRM v5 no longer registers Resource Providers by default.
  resource_providers_to_register = ["Microsoft.Network"]
}

provider "azurerm" {
  alias           = "hub"
  subscription_id = var.hub_subscription_id
  features {}

  resource_providers_to_register = ["Microsoft.Network"]
}

module "vnet-spoke" {
  source = "../../"

  providers = {
    azurerm.hub = azurerm.hub
  }

  # ...
}
```

See [`main.tf`](main.tf) for the full configuration.

## Terraform Usage

Set the required input variables, either in a `terraform.tfvars` file or on the command
line:

```hcl
spoke_subscription_id                = "00000000-0000-0000-0000-000000000000"
hub_subscription_id                  = "11111111-1111-1111-1111-111111111111"
hub_virtual_network_name             = "vnet-infra-hub"
hub_resource_group_name              = "rg-vnet-infra-hub"
private_dns_zone_resource_group_name = "rg-infra-privatedns-zones"
```

Then run:

```shell
terraform init
terraform plan
terraform apply
```

Run `terraform destroy` when you don't need these resources.

> The identity running Terraform needs permission in the hub subscription to read the
> Private DNS zones and to create the virtual network links and the hub-to-spoke peering.
> Every zone named in `private_dns_zone_names` must already exist in
> `private_dns_zone_resource_group_name`.

## Inputs

Name | Description | Type
---- | ----------- | ----
`spoke_subscription_id` | The ID of the Azure subscription the spoke network is deployed into | string
`hub_subscription_id` | The ID of the Azure subscription hosting the hub network | string
`hub_virtual_network_name` | The name of the hub virtual network to peer the spoke with | string
`hub_resource_group_name` | The name of the resource group containing the hub virtual network | string
`private_dns_zone_resource_group_name` | The resource group in the hub subscription that holds the Private DNS Zones | string

## Outputs

|Name | Description|
|---- | -----------|
`resource_group_name`|The name of the resource group in which resources are created
`resource_group_id`|The id of the resource group in which resources are created
`resource_group_location`|The location of the resource group in which resources are created
`virtual_network_name`|The name of the virtual network.
`virtual_network_id`|The virtual network ID.
`virtual_network_address_space`|List of address spaces that are used the virtual network.
`subnet_ids`|Map of subnet keys to subnet IDs
`subnet_address_prefixes`|List of address prefix for subnets
`ddos_protection_plan_id`|Azure Network DDoS protection plan id
`network_watcher_id`|ID of Network Watcher
`route_table_name`|The name of the route table
`route_table_id`|The resource id of the route table
