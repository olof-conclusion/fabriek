# Identity / naming
variable "client_slug" {
  type        = string
  description = "Short slug naming the client portal, e.g. facilicom-mvp or acme. Drives all resource names. Lowercase alphanumeric + hyphens; max 18 chars (KV / Storage Account names are 24 chars max and the longest prefix we add is 4)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,16}[a-z0-9]$", var.client_slug))
    error_message = "client_slug must be 3-18 chars, lowercase alphanumeric + hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Target resource group (must already exist — created by bootstrap-client.sh)."
}

variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region. Drives the `weu` slot in resource names by convention."
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Toggles
variable "enable_database" {
  type    = bool
  default = true
}

variable "enable_key_vault" {
  type    = bool
  default = true
}

variable "enable_blob_storage" {
  type    = bool
  default = false
}

variable "use_shared_acr" {
  type        = bool
  default     = false
  description = "false → create a per-client ACR; true → reference an existing shared ACR."

  validation {
    condition     = !var.use_shared_acr || (var.shared_acr_name != "" && var.shared_acr_resource_group != "")
    error_message = "shared_acr_name and shared_acr_resource_group are required when use_shared_acr = true."
  }
}

variable "shared_acr_name" {
  type    = string
  default = ""
}

variable "shared_acr_resource_group" {
  type    = string
  default = ""
}

# Sizing
variable "app_service_sku" {
  type    = string
  default = "B2"
}

variable "postgres_sku" {
  type        = string
  default     = "B_Standard_B1ms"
  description = "Azure Postgres Flexible sku_name (tier-prefixed, e.g. B_Standard_B1ms, GP_Standard_D2s_v3)."
}

# App
variable "container_image" {
  type        = string
  description = "Container image, repo:tag form (e.g. portal:v1.2.3). The module prepends the ACR login server."
}
