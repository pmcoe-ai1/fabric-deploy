# Kubernetes Namespaces
# Design Reference: Section 7.2 (Environment Isolation)
# All 8 namespaces required by the FABRIC platform

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.fabric.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.fabric.kube_config[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "fabric" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "fabric/environment"           = contains(["staging", "production"], each.value) ? each.value : "shared"
    }
  }
}
