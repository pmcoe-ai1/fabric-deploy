# Terraform State Backend — Azure Blob Storage
# Design Reference: Section 7.2 — state stored in cloud object storage, never locally or in Git

terraform {
  backend "azurerm" {
    resource_group_name  = "fabric-tfstate-rg"
    storage_account_name = "fabrictfstatepmcoe"
    container_name       = "tfstate"
    key                  = "fabric.tfstate"
  }
}
