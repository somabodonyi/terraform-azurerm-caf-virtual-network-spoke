variable "spoke_subscription_id" {
  description = "The ID of the Azure subscription the spoke network is deployed into."
  type        = string
}

variable "hub_subscription_id" {
  description = "The ID of the Azure subscription hosting the hub network. Can be the same as the spoke subscription."
  type        = string
}

variable "hub_virtual_network_name" {
  description = "The name of the hub virtual network to peer the spoke with."
  type        = string
}

variable "hub_resource_group_name" {
  description = "The name of the resource group containing the hub virtual network."
  type        = string
}

variable "private_dns_zone_resource_group_name" {
  description = "The name of the resource group in the hub subscription that holds the Private DNS Zones."
  type        = string
}
