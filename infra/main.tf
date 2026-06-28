variable "image_tag" {
  description = "Container image tag to deploy (the deploy workflow passes the git sha)."
  type        = string
  default     = "latest"
}

resource "azurerm_resource_group" "app" {
  name     = "rg-kvk-viewer"
  location = "westeurope"
}

module "app" {
  source = "./modules/b2ab-app-baseline"
  client_slug         = "kvk-viewer"
  resource_group_name = azurerm_resource_group.app.name
  location            = "westeurope"
  container_image     = "kvk-viewer:${var.image_tag}"

}

# Surfaced for the deploy workflow (docker push target + the app to restart).
output "acr_login_server" {
  value = module.app.acr_login_server
}

output "app_service_name" {
  value = module.app.app_service_name
}

output "app_url" {
  value = module.app.app_url
}
