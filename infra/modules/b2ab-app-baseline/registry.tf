# Per-app registry (default)
module "acr" {
  count                    = var.use_shared_acr ? 0 : 1
  source                   = "Azure/avm-res-containerregistry-registry/azurerm"
  version                  = "0.4.0"
  name                     = local.acr_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  zone_redundancy_enabled  = false # Premium-only feature
  retention_policy_in_days = 0     # retention policy is Premium-only; disable it
  tags                     = local.tags
}

# Shared registry (when use_shared_acr = true)
data "azurerm_container_registry" "shared" {
  count               = var.use_shared_acr ? 1 : 0
  name                = var.shared_acr_name
  resource_group_name = var.shared_acr_resource_group
}

locals {
  acr_id           = var.use_shared_acr ? data.azurerm_container_registry.shared[0].id : module.acr[0].resource_id
  acr_login_server = var.use_shared_acr ? data.azurerm_container_registry.shared[0].login_server : module.acr[0].resource.login_server
}

# Let the app's identity pull images (works for per-app or cross-RG shared ACR).
# The deploy SP gets User Access Administrator on the project RG via the
# bootstrap script, so this role assignment runs as part of `terraform apply`
# without needing a second admin pass.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = local.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.uami.principal_id
}
