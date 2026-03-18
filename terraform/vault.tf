# HashiCorp Vault — Secrets Management
# Design Reference: Section 10 (Secrets & Security)
# Decision #3: Self-hosted on AKS, HA mode with Raft storage, Azure Key Vault auto-unseal
#
# Deployed via Helm to vault namespace.
# HA mode with 3 replicas using integrated Raft storage.
# Auto-unseal via Azure Key Vault (managed identity).
# UI exposed via NGINX Ingress for operator access.

# Azure Key Vault for Vault auto-unseal
resource "azurerm_key_vault" "vault_unseal" {
  name                       = "${var.cluster_name}-unseal"
  location                   = azurerm_resource_group.fabric.location
  resource_group_name        = azurerm_resource_group.fabric.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  tags = merge(var.tags, { component = "vault" })
}

# Access policy for AKS managed identity to use Key Vault for auto-unseal
resource "azurerm_key_vault_access_policy" "vault_unseal" {
  key_vault_id = azurerm_key_vault.vault_unseal.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.fabric.kubelet_identity[0].object_id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey",
  ]
}

# Auto-unseal key in Azure Key Vault
resource "azurerm_key_vault_key" "vault_unseal" {
  name         = "vault-unseal-key"
  key_vault_id = azurerm_key_vault.vault_unseal.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]

  depends_on = [azurerm_key_vault_access_policy.vault_unseal]
}

# Data source for current Azure client config (tenant ID, etc.)
data "azurerm_client_config" "current" {}

# Vault Helm release — HA with Raft storage
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.28.0"
  namespace  = "vault"

  depends_on = [
    kubernetes_namespace.fabric["vault"],
    azurerm_key_vault_key.vault_unseal,
  ]

  # HA mode with Raft integrated storage
  set {
    name  = "server.ha.enabled"
    value = "true"
  }

  set {
    name  = "server.ha.replicas"
    value = "3"
  }

  set {
    name  = "server.ha.raft.enabled"
    value = "true"
  }

  set {
    name  = "server.ha.raft.setNodeId"
    value = "true"
  }

  # Azure Key Vault auto-unseal configuration
  # Defect 19 fix: added tenant_id — required for Azure AD authentication
  set {
    name  = "server.ha.raft.config"
    value = <<-EOT
      ui = true

      listener "tcp" {
        tls_disable = 1
        address     = "[::]:8200"
        cluster_address = "[::]:8201"
      }

      storage "raft" {
        path = "/vault/data"
      }

      seal "azurekeyvault" {
        vault_name = "${azurerm_key_vault.vault_unseal.name}"
        key_name   = "${azurerm_key_vault_key.vault_unseal.name}"
        tenant_id  = "${data.azurerm_client_config.current.tenant_id}"
      }

      service_registration "kubernetes" {}
    EOT
  }

  # Node selector — system pool
  set {
    name  = "server.nodeSelector.fabric/pool"
    value = "system"
  }

  # Vault UI
  set {
    name  = "ui.enabled"
    value = "true"
  }

  set {
    name  = "ui.serviceType"
    value = "ClusterIP"
  }

  # Ingress for Vault UI via NGINX
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "server.ingress.hosts[0].host"
    value = "vault.${var.dns_zone_name}"
  }

  set {
    name  = "server.ingress.hosts[0].paths[0]"
    value = "/"
  }

  # Resource requests for system pool
  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }

  # Metrics for Prometheus
  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  # Data storage
  set {
    name  = "server.dataStorage.enabled"
    value = "true"
  }

  set {
    name  = "server.dataStorage.size"
    value = "10Gi"
  }

  # Injector for sidecar injection
  set {
    name  = "injector.enabled"
    value = "true"
  }

  set {
    name  = "injector.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "injector.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "injector.resources.requests.memory"
    value = "64Mi"
  }
}
