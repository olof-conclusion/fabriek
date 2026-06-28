terraform {
  backend "azurerm" {
    resource_group_name  = "rg-kvk-viewer-tfstate"
    storage_account_name = "stkvkviewertf"
    container_name       = "tfstate"
    key                  = "app.tfstate"
    subscription_id      = "934cff5d-378e-4fbc-8896-1f64c29eb1ec"
  }
}
