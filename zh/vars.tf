variable "customer" {
  type = string
  description = "Customer name/acronym (keep to 3-4 letters)"
  default = "tmc"
}

variable "environment" {
  type = string
  description = "Prod or Dev?"
  default = "dev"
}

/*variable "rg_name" {
  type = string
  description = "The name of the resource group to be provisioned"
  default = "rg-storage"
}*/


variable "rg_location" {
  type = string
  description = "Where to provision your resources (eastus, eastus2, westus, centralus)"
  default = "westus2"
}

variable "storage_tier" {
  type = string
  description = "The storage account tier. Options: Standard or Premium"
  default = "standard"
}

variable "storage_replication" {
  type = string
  description = "The storage acount replication type. Options: LRS, GRS, RAGRS and ZRS"
  default = "LRS"
}

variable "storage_version" {
  type = string
  description = "The storage account version. Options: BlobStorage, BlockBlobStorage, FileStorage, Storage and StorageV2"
  default = "StorageV2"
}

variable "kv_guid" {
  type = string
  description = "GUID of users allowed to access Key Vault. GUID can be found in AAD."
  default = "3f239fa4-91dc-46b7-80f3-93c8f029d58f"
}