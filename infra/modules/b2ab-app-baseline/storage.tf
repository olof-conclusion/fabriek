module "storage" {
  count                    = var.enable_blob_storage ? 1 : 0
  source                   = "Azure/avm-res-storage-storageaccount/azurerm"
  version                  = "0.5.0"
  name                     = local.st_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_replication_type = "LRS"
  tags                     = local.tags

  public_network_access_enabled = false

  private_endpoints = {
    blob = {
      subnet_resource_id = module.vnet.subnets["pe"].resource_id
      subresource_name   = "blob"
    }
  }
}
