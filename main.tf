terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.96.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 1.0.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "> 3.4.3"
    }
  }
}
provider "azurerm" {
  features {}
  storage_use_azuread = true
}
provider "azuredevops" {
  personal_access_token = var.PAT_token
  org_service_url       = var.AzDo_service_url
}

data "azurerm_client_config" "current" {}
resource "random_integer" "int" {
  min = 1
  max = 999
}
resource "azurerm_resource_group" "rg" {
  count    = length(var.environments_list)
  name     = "rg-bairma-${var.project_name}-${var.environments_list[count.index]}-tfstate"
  location = "West Europe"
}
resource "azurerm_user_assigned_identity" "uai" {
  count               = length(var.environments_list)
  name                = "uai-bairma-${var.project_name}-${var.environments_list[count.index]}-tfstate"
  resource_group_name = azurerm_resource_group.rg[count.index].name
  location            = azurerm_resource_group.rg[count.index].location
}
resource "azurerm_storage_account" "st" {
  count                           = length(var.environments_list)
  name                            = "sttf${lower(var.project_name)}${lower(var.environments_list[count.index])}${random_integer.int.result}"
#  name                            = "sttf${var.project_name,,}${var.environments_list[count.index]}${random_integer.int.result}"
  resource_group_name             = azurerm_resource_group.rg[count.index].name
  location                        = azurerm_resource_group.rg[count.index].location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = "false"
  allow_nested_items_to_be_public = false
  is_hns_enabled                  = "true"
  account_kind                    = "StorageV2"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai[count.index].id]
  }
  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.key[count.index].id
    user_assigned_identity_id = azurerm_user_assigned_identity.uai[count.index].id
  }
  depends_on = [azurerm_role_assignment.RBAC_crypto_officer_uai, azurerm_role_assignment.RBAC_crypto_Officer_spn]
}

resource "azurerm_storage_data_lake_gen2_filesystem" "fs" {
  name                = "bairmasynapse${count.index}"
  storage_account_id  = azurerm_storage_account.st[count.index].id
  count               = length(var.environments_list)
}

resource "azurerm_synapse_workspace" "bairma_synapse" {
  count                                 = length(var.environments_list)
  name                                  = "bairma-synapseworkspace-${var.environments_list[count.index]}"
  resource_group_name                   = azurerm_resource_group.rg[count.index].name
  location                              = azurerm_resource_group.rg[count.index].location
  storage_data_lake_gen2_filesystem_id  = azurerm_storage_data_lake_gen2_filesystem.fs[count.index].id
  sql_administrator_login               = "sqladmin"
  sql_administrator_login_password      = "Password_123"

  identity {
    type = "SystemAssigned"
  }
}
resource "azurerm_synapse_workspace_aad_admin" "aad_admin" {
  count                = length(var.environments_list)
  synapse_workspace_id = azurerm_synapse_workspace.bairma_synapse[count.index].id
  login                = "AzureAD Admin"
  object_id            = data.azurerm_client_config.current.object_id
  tenant_id            = data.azurerm_client_config.current.tenant_id
}

resource "azurerm_storage_container" "container" {
  count                 = length(var.environments_list)
  name                  = "bairma-tfstatecont01"
  storage_account_name  = azurerm_storage_account.st[count.index].name
  container_access_type = "private"
}
resource "azurerm_key_vault" "vault" {
  count                      = length(var.environments_list)
  name                       = "kv-${var.project_name}${var.environments_list[count.index]}${random_integer.int.result}"
  resource_group_name        = azurerm_resource_group.rg[count.index].name
  location                   = azurerm_resource_group.rg[count.index].location
  tenant_id                  = var.environment_credentials[var.environments_list[count.index]].tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}
resource "azurerm_key_vault_key" "key" {
  count        = length(var.environments_list)
  name         = "tfstate-key-bairma"
  key_vault_id = azurerm_key_vault.vault[count.index].id
  key_type     = "RSA"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "verify", "unwrapKey", "wrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
  depends_on = [azurerm_role_assignment.RBAC_crypto_Officer_spn]
}
resource "azurerm_role_assignment" "RBAC_blob_data_owner_spn" {
  count                = length(var.environments_list)
  scope                = azurerm_storage_account.st[count.index].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.environment_credentials[var.environments_list[count.index]].service_principal_object_id
}
resource "azurerm_role_assignment" "RBAC_Storage_account_contributor_spn" {
  count                = length(var.environments_list)
  scope                = azurerm_storage_account.st[count.index].id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.environment_credentials[var.environments_list[count.index]].service_principal_object_id
}
resource "azurerm_role_assignment" "RBAC_crypto_Officer_spn" {
  count                = length(var.environments_list)
  scope                = azurerm_key_vault.vault[count.index].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = var.environment_credentials[var.environments_list[count.index]].service_principal_object_id
}
resource "azurerm_role_assignment" "RBAC_crypto_officer_uai" {
  count                = length(var.environments_list)
  scope                = azurerm_key_vault.vault[count.index].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_user_assigned_identity.uai[count.index].principal_id
}
