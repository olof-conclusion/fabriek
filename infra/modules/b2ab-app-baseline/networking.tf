module "vnet" {
  source              = "Azure/avm-res-network-virtualnetwork/azurerm"
  version             = "0.8.1"
  name                = local.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.40.0.0/22"]
  tags                = local.tags

  subnets = {
    app = {
      name             = local.app_subnet
      address_prefixes = ["10.40.0.0/24"]
      delegation = [{
        name = "appservice"
        service_delegation = {
          name = "Microsoft.Web/serverFarms"
        }
      }]
    }
    pe = {
      name                              = local.pe_subnet
      address_prefixes                  = ["10.40.1.0/24"]
      private_endpoint_network_policies = "Disabled"
    }
  }
}
