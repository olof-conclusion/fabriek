resource "azurerm_private_dns_zone" "pg" {
  count               = var.enable_database ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "pg" {
  count                 = var.enable_database ? 1 : 0
  name                  = "pg-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.pg[0].name
  virtual_network_id    = module.vnet.resource_id
}

resource "random_password" "pg" {
  count   = var.enable_database ? 1 : 0
  length  = 24
  special = true
  # avoid characters Postgres rejects in the admin password
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "postgres" {
  count                  = var.enable_database ? 1 : 0
  source                 = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version                = "0.2.2"
  name                   = local.pg_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  server_version         = "16"
  sku_name               = var.postgres_sku
  storage_mb             = 32768
  administrator_login    = "b2abadmin"
  administrator_password = random_password.pg[0].result
  high_availability      = null # burstable SKUs don't support HA
  tags                   = local.tags

  private_endpoints = {
    pg = {
      subnet_resource_id            = module.vnet.subnets["pe"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.pg[0].id]
    }
  }
}
