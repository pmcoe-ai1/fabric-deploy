# FABRIC Infrastructure Outputs

output "cluster_name" {
  value       = azurerm_kubernetes_cluster.fabric.name
  description = "AKS cluster name"
}

output "cluster_id" {
  value       = azurerm_kubernetes_cluster.fabric.id
  description = "AKS cluster resource ID"
}

output "kube_config_raw" {
  value       = azurerm_kubernetes_cluster.fabric.kube_config_raw
  sensitive   = true
  description = "Raw kubeconfig for cluster access"
}

output "resource_group_name" {
  value       = azurerm_resource_group.fabric.name
  description = "Resource group name"
}

output "cluster_fqdn" {
  value       = azurerm_kubernetes_cluster.fabric.fqdn
  description = "AKS cluster FQDN"
}
