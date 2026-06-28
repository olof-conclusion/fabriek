data "azurerm_client_config" "current" {}

module "keyvault" {
  count               = var.enable_key_vault ? 1 : 0
  source              = "Azure/avm-res-keyvault-vault/azurerm"
  version             = "0.9.1"
  name                = local.kv_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  public_network_access_enabled = false

  # Deploy SP has User Access Administrator on the project RG (set by
  # bootstrap-client.sh), so this assignment runs as part of `terraform apply`.
  role_assignments = {
    app_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.uami.principal_id
    }
  }

  private_endpoints = {
    kv = {
      subnet_resource_id = module.vnet.subnets["pe"].resource_id
    }
  }
}
