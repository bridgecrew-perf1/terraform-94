terraform {   
  backend "azurerm" {  
  resource_group_name   = "rg"
  storage_account_name  = "sa-name"
  container_name        = "tfstate"  
  key                   = "dev.tfstate" #This line is the actual filename of the TF state file stored on blob  
 } 
}

  
# Configure the Azure Provider
provider "azurerm" {
  version = "=2.14.0"
  features {}

}

data "azurerm_client_config" "current" {}

locals{
  name_env = "${var.customer}"
}


#Provide a randomized numeric string for globally unique resource naming requirements
resource "random_string" "random" {
  length  = 4
  special = false
  upper   = false
  lower   = false 
}

#Create RG in WestUS2
resource "azurerm_resource_group" "int_rg" {
  name     = "rg"
  location = "westus2"
}

#Create RG in WestUS2
resource "azurerm_resource_group" "app_rg" {
  name     = "rg"
  location = "westus2"
}

#Create RG in WestUS2
resource "azurerm_resource_group" "shared_rg" {
  name     = "zhealth-sharedsvcs-dev-01-rg"
  location = "westus2"
}

#Create RG in WestUS2
resource "azurerm_resource_group" "data_rg" {
  name     = "rg"
  location = "westus2"
}

#Add a data source for referencing the stored secret in vault
data "azurerm_key_vault_secret" "sql_secret" {
  name         = var.kv_secret_name
  key_vault_id = "/subscriptions/20be82de-19bd-44aa-bda7-3345f7c6d5ad/resourceGroups/westus2-managed-services-rg/providers/Microsoft.KeyVault/vaults/kv-admin-01"
}


#Create an azure storage account v2 that will house a blob container
resource "azurerm_storage_account" "blob_sa" {
  name                        = "zhdevblob${random_string.random.result}"
  resource_group_name         = azurerm_resource_group.data_rg.name
  location                    = azurerm_resource_group.data_rg.location
  account_tier                = "standard"
  account_replication_type    = "lrs"
  account_kind                = "StorageV2"
  is_hns_enabled              = "false"

  tags = {
    environment = "dev"
  }
}

#SQL Server w/ elastic pool for Data layer and will house the Shard Mapping
resource "azurerm_mssql_server" "zh_mssql" {
  name                         = var.mssql_svr_name
  resource_group_name          = azurerm_resource_group.data_rg.name
  location                     = azurerm_resource_group.data_rg.location
  version                      = "12.0"
  administrator_login          = var.mssql_user
  administrator_login_password = data.azurerm_key_vault_secret.sql_secret.value

  extended_auditing_policy {
    storage_endpoint                        = azurerm_storage_account.blob_sa.primary_blob_endpoint
    storage_account_access_key              = azurerm_storage_account.blob_sa.primary_access_key
    storage_account_access_key_is_secondary = true
    retention_in_days                       = 6
  }

  azuread_administrator {
    login_username = "AzureAD Admin"
    object_id      = "2fb07eb7-88e7-44f5-8c0e-d222f2970071"
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_mssql_elasticpool" "zh_elastipool" {
  name                = var.mssql_pool_name
  resource_group_name = azurerm_resource_group.data_rg.name
  location            = azurerm_resource_group.data_rg.location
  server_name         = azurerm_mssql_server.zh_mssql.name
  license_type        = "LicenseIncluded"
  max_size_gb         = 750
  
  sku {
    name     = "StandardPool"
    capacity = "100"
    tier     = "Standard"
    }

  per_database_settings {
    min_capacity = "0"
    max_capacity = "100"
  }
}

#Mirth PostgreSQL instance
resource "azurerm_postgresql_server" "zh_pgsql" {
  name                = var.pgsql_svr_name
  resource_group_name = azurerm_resource_group.data_rg.name
  location            = azurerm_resource_group.data_rg.location

  administrator_login          = var.pgsql_user
  administrator_login_password = data.azurerm_key_vault_secret.sql_secret.value

  sku_name   = "B_Gen5_1"
  version    = "11"
  storage_mb = "256000"

  backup_retention_days        = 7
  #Features only available in GP or Memory Opt. SKUs
  #geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  #public_network_access_enabled    = false
  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
}

#key vault for integration zone
resource "azurerm_key_vault" "integration_kv" {
  name                            = format("kv-int-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location                        = azurerm_resource_group.int_rg.location
  resource_group_name             = azurerm_resource_group.int_rg.name
  enabled_for_template_deployment = true
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled             = true
  purge_protection_enabled        = false
  sku_name                        = "standard"
  
  access_policy {
    tenant_id       = data.azurerm_client_config.current.tenant_id
    object_id       = "640afd29-b0da-4b20-ae47-6b2718dd6033"
    
    key_permissions = [
      "create","decrypt","delete","encrypt","get","import","list","purge","recover","restore","sign","unwrapKey","update","verify","wrapKey"
    ]
    secret_permissions = [
      "backup", "delete", "get", "list", "purge", "recover", "restore", "set"
    ]
    storage_permissions = [
      "backup","delete","deletesas","get","getsas","list","listsas","purge","recover","regeneratekey","restore","set","setsas","update"
    ]
    certificate_permissions = [
      "backup","create","delete","deleteissuers","get","getissuers","import","list","listissuers","managecontacts","manageissuers","purge","recover","restore","setissuers","update"
    ]
  }


}

 #commenting out restrictive policy
  /*access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = var.kv_guid

    key_permissions = [ "backup", "create", "decrypt", "delete", "encrypt", "get", "import", "list", "purge", 
                  "recover", "restore", "sign", "unwrapKey","update", "verify", "wrapKey" ]

    secret_permissions = [ "backup", "delete", "get", "list", "purge", "recover", "restore", "set" ]

    storage_permissions = [ "backup", "delete", "deletesas", "get", "getsas", "list", "listsas", 
                  "purge", "recover", "regeneratekey", "restore", "set", "setsas", "update" ]
  }

    network_acls {
        default_action             = "Deny"
        bypass                     = "AzureServices"
        ip_rules                   = ["72.52.134.124/32", "13.90.134.170/32"]
    }
}*/

#key vault for application zone

resource "azurerm_key_vault" "app_kv" {
  name                            = format("kv-app-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location                        = azurerm_resource_group.app_rg.location
  resource_group_name             = azurerm_resource_group.app_rg.name
  enabled_for_template_deployment = true
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled             = true
  purge_protection_enabled        = false
  sku_name                        = "standard"
  
  access_policy {
    tenant_id       = data.azurerm_client_config.current.tenant_id
    object_id       = "640afd29-b0da-4b20-ae47-6b2718dd6033"
    
    key_permissions = [
      "create","decrypt","delete","encrypt","get","import","list","purge","recover","restore","sign","unwrapKey","update","verify","wrapKey"
    ]
    secret_permissions = [
      "backup", "delete", "get", "list", "purge", "recover", "restore", "set"
    ]
    storage_permissions = [
      "backup","delete","deletesas","get","getsas","list","listsas","purge","recover","regeneratekey","restore","set","setsas","update"
    ]
    certificate_permissions = [
      "backup","create","delete","deleteissuers","get","getissuers","import","list","listissuers","managecontacts","manageissuers","purge","recover","restore","setissuers","update"
    ]
  }

}

#commenting out restrictive policy
  /*access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = var.kv_guid

    key_permissions = [ "backup", "create", "decrypt", "delete", "encrypt", "get", "import", "list", "purge", 
                  "recover", "restore", "sign", "unwrapKey","update", "verify", "wrapKey" ]

    secret_permissions = [ "backup", "delete", "get", "list", "purge", "recover", "restore", "set" ]

    storage_permissions = [ "backup", "delete", "deletesas", "get", "getsas", "list", "listsas", 
                  "purge", "recover", "regeneratekey", "restore", "set", "setsas", "update" ]
  }

    network_acls {
        default_action             = "Deny"
        bypass                     = "AzureServices"
        ip_rules                   = ["72.52.134.124/32", "13.90.134.170/32"]
    }
}*/

resource "azurerm_servicebus_namespace" "etch_bus" {
  name                = "${var.customer}-eih2etch-bus"
  location            = azurerm_resource_group.shared_rg.location
  resource_group_name = azurerm_resource_group.shared_rg.name
  sku                 = "Standard"

  tags = {
    environment = "dev"
  }
}

#integration zone ACR
resource "azurerm_container_registry" "int_acr" {
  name                     = format("acrapp%s%s", lower(replace(var.initials, "/[[:^alnum:]]/", "")), random_string.random.result)
  resource_group_name      = azurerm_resource_group.int_rg.name
  location                 = azurerm_resource_group.int_rg.location
  sku                      = "Standard"
  admin_enabled            = false
#feature only supported for premium SKU  
#georeplication_locations = ["East US", "West Europe"]
}

#app zone ACR
resource "azurerm_container_registry" "app_acr" {
  name                     = format("acrint%s%s", lower(replace(var.initials, "/[[:^alnum:]]/", "")), random_string.random.result)
  resource_group_name      = azurerm_resource_group.app_rg.name
  location                 = azurerm_resource_group.app_rg.location
  sku                      = "Standard"
  admin_enabled            = false
#feature only supported for premium SKU  
#georeplication_locations = ["East US", "West Europe"]
}


#Etch API App service plan and web app config
resource "azurerm_app_service_plan" "etchapi_plan" {
  name                = format("plan-etchapi-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  kind                = "windows"
  
  sku {
    tier = "PremiumV2"
    size = "P1V2"
    capacity = 2
  }
}

resource "azurerm_app_service" "etchapi_app" {
  name                = format("app-etchapi-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  app_service_plan_id = azurerm_app_service_plan.etchapi_plan.id

  site_config {
    dotnet_framework_version = "v4.0"
    scm_type                 = "LocalGit"
  }

  app_settings = {
    
  }
}

#Code Engine App service plan and web app config
resource "azurerm_app_service_plan" "engine_plan" {
  name                = format("plan-engine-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  kind                = "windows"
  
  sku {
    tier = "PremiumV2"
    size = "P1V2"
    capacity = 2
  }
}

resource "azurerm_app_service" "engine_app" {
  name                = format("app-engine-%s%s", lower(replace(var.customer, "/[[:^alnum:]]/", "")), random_string.random.result)
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  app_service_plan_id = azurerm_app_service_plan.engine_plan.id

  site_config {
    dotnet_framework_version = "v4.0"
    scm_type                 = "LocalGit"
  }

  app_settings = {
    
  }
}


