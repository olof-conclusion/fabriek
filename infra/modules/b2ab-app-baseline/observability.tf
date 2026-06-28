module "law" {
  source              = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version             = "0.4.2"
  name                = local.law_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

module "appinsights" {
  source              = "Azure/avm-res-insights-component/azurerm"
  version             = "0.1.5"
  name                = local.appi_name
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = module.law.resource_id
  application_type    = "web"
  tags                = local.tags
}
