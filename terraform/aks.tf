# FABRIC AKS Cluster Configuration
# Design Reference: Section 7.1 (Infrastructure Components), Section 7.2 (Environment Isolation)
# Decision #2: Single cluster with namespace isolation (staging/production)

# Resource Group for all FABRIC resources
resource "azurerm_resource_group" "fabric" {
  name     = var.resource_group_name
  location = var.location
  tags     = merge(var.tags, { environment = var.environment })
}

# Explicit VNet for AKS and PostgreSQL
# Defect 16 fix: AKS with Azure CNI creates VNet in MC_* resource group.
# We need an explicit VNet in fabric-rg for PostgreSQL private access.
resource "azurerm_virtual_network" "fabric" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.fabric.location
  resource_group_name = azurerm_resource_group.fabric.name
  address_space       = ["10.0.0.0/8"]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.fabric.name
  virtual_network_name = azurerm_virtual_network.fabric.name
  address_prefixes     = ["10.0.0.0/16"]
}

# AKS Cluster — single cluster, namespace isolation
resource "azurerm_kubernetes_cluster" "fabric" {
  name                = var.cluster_name
  location            = azurerm_resource_group.fabric.location
  resource_group_name = azurerm_resource_group.fabric.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  # System node pool: Argo CD, Vault, Prometheus, Grafana, Loki, Tempo, ESO, NGINX Ingress, Argo Rollouts
  default_node_pool {
    name                        = "system"
    node_count                  = var.system_node_count
    vm_size                     = var.system_node_vm_size
    os_disk_size_gb             = 50
    enable_auto_scaling         = false
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    temporary_name_for_rotation = "tmpsystem"

    node_labels = {
      "fabric/pool" = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  tags = merge(var.tags, { environment = var.environment })
}

# Application node pool: FABRIC application pods
# Conditional: skipped when app_node_count = 0 (e.g., sandbox vCPU quota limits)
resource "azurerm_kubernetes_cluster_node_pool" "app" {
  count                 = var.app_node_count > 0 ? 1 : 0
  name                  = "app"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.fabric.id
  vm_size               = var.app_node_vm_size
  node_count            = var.app_node_count
  os_disk_size_gb       = 50
  enable_auto_scaling   = false

  node_labels = {
    "fabric/pool" = "app"
  }

  tags = merge(var.tags, { environment = var.environment })
}

# Namespace list per Section 7.2 and CLAUDE.md
locals {
  namespaces = [
    "staging",
    "production",
    "argocd",
    "argo-rollouts",
    "vault",
    "monitoring",
    "external-secrets",
    "ingress-nginx",
  ]
}
