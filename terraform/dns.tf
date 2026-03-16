# Azure DNS — Public DNS Zone and Records
# Design Reference: Section 7.1 (Infrastructure Components)
# Task B-04: DNS zone with A records pointing to NGINX Ingress external IP
#
# Records:
#   staging.fabric.{domain} → NGINX Ingress external IP
#   fabric.{domain}         → NGINX Ingress external IP (production)
#   argocd.{domain}         → NGINX Ingress external IP
#   vault.{domain}          → NGINX Ingress external IP
#   grafana.{domain}        → NGINX Ingress external IP

resource "azurerm_dns_zone" "fabric" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.fabric.name
  tags                = merge(var.tags, { component = "dns" })
}

# Data source to get NGINX Ingress Controller external IP
# The LoadBalancer IP is provisioned by the NGINX Ingress Helm release
data "kubernetes_service" "nginx_ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.nginx_ingress]
}

locals {
  ingress_ip = data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
}

# Staging application endpoint
resource "azurerm_dns_a_record" "staging" {
  name                = "staging"
  zone_name           = azurerm_dns_zone.fabric.name
  resource_group_name = azurerm_resource_group.fabric.name
  ttl                 = 300
  records             = [local.ingress_ip]
}

# Production application endpoint
resource "azurerm_dns_a_record" "production" {
  name                = "@"
  zone_name           = azurerm_dns_zone.fabric.name
  resource_group_name = azurerm_resource_group.fabric.name
  ttl                 = 300
  records             = [local.ingress_ip]
}

# Argo CD UI
resource "azurerm_dns_a_record" "argocd" {
  name                = "argocd"
  zone_name           = azurerm_dns_zone.fabric.name
  resource_group_name = azurerm_resource_group.fabric.name
  ttl                 = 300
  records             = [local.ingress_ip]
}

# Vault UI
resource "azurerm_dns_a_record" "vault" {
  name                = "vault"
  zone_name           = azurerm_dns_zone.fabric.name
  resource_group_name = azurerm_resource_group.fabric.name
  ttl                 = 300
  records             = [local.ingress_ip]
}

# Grafana dashboards
resource "azurerm_dns_a_record" "grafana" {
  name                = "grafana"
  zone_name           = azurerm_dns_zone.fabric.name
  resource_group_name = azurerm_resource_group.fabric.name
  ttl                 = 300
  records             = [local.ingress_ip]
}

# Output the DNS zone name servers for domain registrar delegation
output "dns_zone_name_servers" {
  value       = azurerm_dns_zone.fabric.name_servers
  description = "Name servers for the DNS zone — configure these at your domain registrar"
}
