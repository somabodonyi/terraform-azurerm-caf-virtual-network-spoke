# Azure Virtual Network Spoke Terraform Module

This module deploys a spoke network using the [Microsoft recommended Hub-Spoke network topology](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke). Usually, only one hub in each region with multiple spokes and each of them can also be in separate subscriptions.

>if you are deploying the spoke VNet in the same Hub Network subscription or more Spoke in the same subscription, then make sure you have set the argument `is_spoke_deployed_to_same_hub_subscription = true`. This helps this module to manage the network watcher. If you are deploying the spoke virtual networks in separate subscriptions, then set this argument to `false`.

This is designed to quickly deploy hub and spoke architecture in the azure and further security hardening would be recommend to add appropriate NSG rules to use this for any production workloads.


## Module Usage

```hcl
module "vnet-spoke" {
  source  = "github.com/bimobject-github/terraform-azurerm-caf-virtual-network-spoke?ref=v1.2.1"
  
  providers = {
    azurerm.hub = azurerm.infra 
   }

  # By default, this module will create a resource group, proivde the name here 
  # to use an existing resource group, specify the existing resource group name, 
  # and set the argument to `create_resource_group = false`. Location will be same as existing RG. 
  create_resource_group = false
  resource_group_name = azurerm_resource_group.rg-vnet-spoke.name
  location            = azurerm_resource_group.rg-vnet-spoke.location
  spoke_vnet_name     = var.vnet_name

  # Specify if you are deploying the spoke VNet using the same hub or another Spoke Azure subscription
  is_spoke_deployed_to_same_hub_subscription = true

  # Provide valid VNet Address space for spoke virtual network.  
  vnet_address_space = var.vnet_address_space

  # Hub network details to create peering and other setup
  hub_virtual_network_id          = data.azurerm_virtual_network.vnet-hub.id 


  # Multiple Subnets, Service delegation, Service Endpoints, Network security groups
  # These are default subnets with required configuration, check README.md for more details
  # Route_table to be added automatically for all subnets listed here.
  subnets = {
    default = {
      subnet_name           = var.snet_default_name
      subnet_address_prefix = var.snet_default_address_prefix 
      service_endpoints     = []
      
    },
    test = {
      subnet_name           = var.snet_webapps_name
      subnet_address_prefix = var.snet_webapps_address_prefix 
      service_endpoints     = []
      delegation = {
            name = "delegation"
            service_delegation = {
                name= "Microsoft.Web/serverFarms"
                actions= ["Microsoft.Network/virtualNetworks/subnets/action"]
            }
         }
    }
  }

  route_table_name= var.rt_name
   routes = [
    { name = var.route_dev_vnet_name, address_prefix = var.route_dev_vnet_address_prefix, next_hop_type = var.route_dev_vnet_next_hop_type}
  ]

  
  create_nat_gateway = true
  nat_gateway_name="ngw-campaign-test"
  public_ip_name="pip-ngw-campaign-test"

  # Adding TAG's to your Azure resources (Required)
  # ProjectName and Env are already declared above, to use them here, create a varible. 
  tags = local.tags

  depends_on = [
    azurerm_resource_group.rg-vnet-spoke
  ] 
} 
```

## terraform.tfvars

```hcl
location           = "northeurope"
vnet_rg_name       = "rg-campaign-vnet"
vnet_address_space = ["10.40.0.0/16"]
vnet_name          = "vnet-campaign"
snet_default_name  = "default"
snet_default_address_prefix = ["10.40.0.0/24"]
snet_webapps_name  = "webapps"
snet_webapps_address_prefix = ["10.40.1.0/24"]
route_dev_vnet_name  = "Any-to-dev-vnet"
route_dev_vnet_address_prefix  = "10.110.0.0/16"
route_dev_vnet_next_hop_type   = "VirtualNetworkGateway"
rt_name = "rt-campaign"
subscription_infra_id = "3c98536d-34b5-4dee-83e6-99559dee47a0"
vnet_infra_name = "vnet-infra-test"
vnet_infra_rg_name = "rg-vnet-infra-test"
peering_spoke_to_hub_name = "peer_campaign_to_infra"
peering_hub_to_spoke_name = "peer_infra_to_campaign" 
tag_application = "Campaign"
tag_team = "Valhalla"
subscription_spoke_id = "f6ec5f46-4aeb-4064-a2dd-2d68e78df2d9"
key_vault_rg_name = "rg-keyvault-campaign-test"
key_vault_name = "kv-campaign-test-test"
key_vault_sku_pricing_tier = "standard"
azure_ad_group_names = ["DS-BPM-Products-Valhalla","DS-Shared-Technology"]
azure_ad_service_principal_names = ["SharedTech-BPM-Test-contributor"]
```


## Create resource group

By default, this module will create a resource group and the name of the resource group to be given in an argument `resource_group_name`. If you want to use an existing resource group, specify the existing resource group name, and set the argument to `create_resource_group = false`.

> *If you are using an existing resource group, then this module uses the same resource group location to create all resources in this module.*

## Hub network reference
Hub virtual network id needs to be provided 
 hub_virtual_network_id          = data.azurerm_virtual_network.vnet-hub.id

## Subnets

This module handles the creation and a list of address spaces for subnets. This module uses `for_each` to create subnets and corresponding service endpoints, service delegation, and network security groups. This module associates the subnets to network security groups as well with additional user-defined NSG rules.  


### Subnet definition with  Microsoft.Web/serverFarms delegation

```hcl

subnets = {
....

test = {
      subnet_name           = var.snet_webapps_name
      subnet_address_prefix = var.snet_webapps_address_prefix 
      service_endpoints     = []
      delegation = {
            name = "delegation"
            service_delegation = {
                name= "Microsoft.Web/serverFarms"
                actions= ["Microsoft.Network/virtualNetworks/subnets/action"]
            }
         }
    }

}
```

## providers

To define the provider a provider section have to be added
  

```hcl  

##providers 
provider "azurerm" {
  alias			  = "infra"
  subscription_id = var.subscription_infra_id
  features {}
}
#############

Module "vnet-spoke"{
 
 .....
  providers = {
    azurerm.hub = azurerm.infra 
   }
 ....
}
```

To make that work azurerm.infra provider have to exits within you provieders


## route table and routes

```hcl  

  route_table_name= var.rt_name
   routes = [
    { name = "Any-to-dev-vnet", address_prefix = "10.110.0.0/16" next_hop_type = "VirtualNetworkGateway"},
    { name = "Any-to-other-vnet", address_prefix = "10.115.0.0/16" next_hop_type = "VirtualNetworkGateway"},
  ]
```
Address_prefix is the address space of the remmote network where the requests needs to be routed.
If you need a new route notify SharedTech as well becasuse maybe the Network Gateway in the hub network need to register this address space

## Network Watcher

This module handle the provision of Network Watcher resource by defining `create_network_watcher` variable. It will enable network watcher, flow logs and traffic analytics for all the subnets in the Virtual Network. Since Azure uses a specific naming standard on network watchers, It will create a resource group `NetworkWatcherRG` and adds the location specific resource.


## Peering to Hub

To peer spoke networks to the hub networks requires the service principal that performs the peering has `Network Operator` custom role on hub network. Linking the Spoke to Hub DNS zones, the service principal also needs the `Private Endpoint Operator` custom role on hub network. If Log Analytics workspace is created in hub or another subscription then, the service principal must have `Log Analytics Contributor` role on workspace or a custom role to connect resources to workspace.

## Private DNS zone registration 
By default privite dns zone registration is enabled. Therefore it register all vnets to the supported private dns zonesdns zones in hub network
In this case the 'private_dns_zone_resource_group_name` parameter is mandatory

```hcl  


Module "vnet-spoke"{
 
 .....
  private_dns_zone_resource_group_name = "rg-infra-test-privatedns-zones"
 ....
}
```

To turn this feature off `private_dns_zone_registration` parameter have to set to false
For custom private dns zone names the `private_dns_zone_names` needs to be provided

```hcl  
  default = {
    privatelink_azurewebsites_net = "privatelink.azurewebsites.net",
    privatelink_database_windows_net = "privatelink.database.windows.net",
    privatelink_documents_azure_com = "privatelink.documents.azure.com"
  }
```
`private_dns_zone_names`  parameter defined as a map because in this it will be added to the state by name not by index if we use only a simple list. 
The modification of the values are safe.
## Requirements

Name | Version
-----|--------
terraform | >= 0.13
azurerm | >= 3.20.0

## Providers

| Name | Version |
|------|---------|
azurerm | >= 3.20.0
random | n/a

## Inputs

Name | Description | Type | Default
---- | ----------- | ---- | -------
`create_resource_group` | Whether to create resource group and use it for all networking resources | string | `true`
`resource_group_name` | The name of the resource group in which resources are created | string | `""`
`location`|The location of the resource group in which resources are created| string | `""`
`spoke_vnet_name`|The name of the spoke virtual network|string | `""`
`is_spoke_deployed_to_same_hub_subscription`|Specify if the Spoke module using the same subscription as Hub|string|`true`
`vnet_address_space`|Virtual Network address space to be used |list|`[]`
`create_ddos_plan` | Controls if DDoS protection plan should be created | string | `"false"`
`dns_servers` | List of DNS servers to use for virtual network | list |`[]`
`subnets`|For each subnet, create an object that contain fields|object|`{}`
`subnet_name`|A name of subnets inside virtual network| object |`{}`
`subnet_address_prefix`|A list of subnets address prefixes inside virtual network|
`delegation`|defines a subnet delegation feature. takes an object as described in the following example|object|`{}`
`service_endpoints`|service endpoints for the virtual subnet|object|`{}`
`hub_virtual_network_id`|The Resource id of the Hub Virtual Network|string|`""`
`route_table_name`|Name of the route table|string|`""`
`routes`|Route table routes|object|`{}`
`use_remote_gateways`|Controls if remote gateways can be used on the local virtual network|string|`false`
`create_nat_gateway`|Whehter create not gateway or not|string|`false`
`nat_gateway_name`|Name of the NAT Gateway|string|`""`
`public_ip_name`|NAT Gateway public IP name|string|`""`
`Tags`|A map of tags to add to all resources|map|`{}`

## Outputs

|Name | Description|
|---- | -----------|
`resource_group_name`|The name of the resource group in which resources are created
`resource_group_id`|The id of the resource group in which resources are created
`resource_group_location`|The location of the resource group in which resources are created
`virtual_network_name`|The name of the virtual network.
`virtual_network_id`|The virtual NetworkConfiguration ID.
`virtual_network_address_space`|List of address spaces that are used the virtual network.
`subnet_ids`|List of IDs of subnets
`subnet_address_prefixes`|List of address prefix for  subnets
`network_security_group_ids`|List of Network security groups and ids
`ddos_protection_plan_id`|Azure Network DDoS protection plan id
`network_watcher_id`|ID of Network Watcher
`route_table_name`|The resource id of the route table
`route_table_id`|The resource id of the route table


## Authors

Originally created by [Kumaraswamy Vithanala](mailto:kumarvna@gmail.com)

Modified by Csaba Gál

## Other resources

* [Hub-spoke network topology in Azure](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
* [Terraform AzureRM Provider Documentation](https://www.terraform.io/docs/providers/azurerm/index.html)
