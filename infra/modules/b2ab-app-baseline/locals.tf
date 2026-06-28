locals {
  # Naming pattern: <prefix>-<client_slug>-weu (or <client_slug>-weu for the bare name).
  # No `cs-` / `ce-` prefix — client-owned resources don't carry the corporate marker.
  # The region marker (`weu`) stays for clarity and so the same client slug can be
  # hosted in multiple regions later without a name collision.
  name = "${var.client_slug}-weu"

  tags = merge({ "client" = var.client_slug }, var.tags)

  vnet_name  = "vnet-${local.name}"
  app_subnet = "snet-app"
  pe_subnet  = "snet-pe"
  app_name   = "app-${local.name}"
  plan_name  = "plan-${local.name}"
  pg_name    = "psql-${local.name}"
  kv_name    = substr("kv-${local.name}", 0, 24)
  law_name   = "log-${local.name}"
  appi_name  = "appi-${local.name}"
  uami_name  = "id-${local.name}"
  # ACR + Storage names: alphanumeric only, lowercase, capped at 24.
  acr_name = substr(lower(replace("acr${local.name}", "-", "")), 0, 50)
  st_name  = substr(lower(replace("st${local.name}", "-", "")), 0, 24)
}
