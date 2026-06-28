output "managed_identity_client_id" {
  value       = module.uami.client_id
  description = "Client ID of the app's user-assigned managed identity."
}

output "acr_login_server" {
  value       = local.acr_login_server
  description = "Login server of the container registry (per-app or shared)."
}

output "app_service_name" {
  value = module.app.name
}

output "app_service_default_hostname" {
  value = module.app.resource_uri
}

output "app_url" {
  value = "https://${module.app.resource_uri}"
}

output "key_vault_uri" {
  value = var.enable_key_vault ? module.keyvault[0].uri : null
}

output "postgres_fqdn" {
  value = var.enable_database ? module.postgres[0].fqdn : null
}
