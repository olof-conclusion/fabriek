module "plan" {
  source                 = "Azure/avm-res-web-serverfarm/azurerm"
  version                = "0.7.0"
  name                   = local.plan_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.app_service_sku
  zone_balancing_enabled = false # not allowed on Basic (B-series) tiers
  tags                   = local.tags
}

module "app" {
  source                   = "Azure/avm-res-web-site/azurerm"
  version                  = "0.17.0"
  name                     = local.app_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  kind                     = "webapp"
  os_type                  = "Linux"
  service_plan_resource_id = module.plan.resource_id
  tags                     = local.tags

  virtual_network_subnet_id = module.vnet.subnets["app"].resource_id

  managed_identities = {
    user_assigned_resource_ids = [module.uami.resource_id]
  }

  site_config = {
    # Pull the image from the private ACR using the app's user-assigned identity
    # (which holds AcrPull). container_image is repo:tag only — the module
    # prepends docker_registry_url to form the full reference.
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = module.uami.client_id
    application_stack = {
      docker = {
        docker_image_name   = var.container_image
        docker_registry_url = "https://${local.acr_login_server}"
      }
    }
    vnet_route_all_enabled            = true
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5
  }

  app_settings = merge(
    {
      APPLICATIONINSIGHTS_CONNECTION_STRING = module.appinsights.connection_string
      AZURE_CLIENT_ID                       = module.uami.client_id
      WEBSITES_PORT                         = "8000"
    },
    var.enable_database ? { DATABASE_FQDN = module.postgres[0].fqdn } : {},
    var.enable_key_vault ? { KEY_VAULT_URI = module.keyvault[0].uri } : {},
  )
}
