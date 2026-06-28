module "uami" {
  source              = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version             = "0.3.3"
  name                = local.uami_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}
