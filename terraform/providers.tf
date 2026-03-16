# FABRIC Infrastructure — Provider Configuration
# Design Reference: FABRIC-CICD-Automation-Design Section 7

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.fabric.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].cluster_ca_certificate)
  }
}
