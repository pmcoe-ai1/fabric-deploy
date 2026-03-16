# Azure Database for PostgreSQL Flexible Server
# Design Reference: Section 7.1 (Infrastructure Components), Section 7.2 (Environment Isolation)
# Decision #8: Reversible migrations (up + down) required before production deployment
#
# Two instances:
#   - Staging: B1ms SKU (burstable, cost-efficient)
#   - Production: D2s_v3 equivalent with zone-redundant HA

# VNet subnet for PostgreSQL private access
resource "azurerm_subnet" "postgresql" {
  name                 = "fabric-postgresql-subnet"
  resource_group_name  = azurerm_resource_group.fabric.name
  virtual_network_name = azurerm_kubernetes_cluster.fabric.name
  address_prefixes     = ["10.1.0.0/24"]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Private DNS zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "fabric.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.fabric.name
  tags                = merge(var.tags, { environment = "shared" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "fabric-postgresql-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  resource_group_name   = azurerm_resource_group.fabric.name
  virtual_network_id    = azurerm_kubernetes_cluster.fabric.network_profile[0].pod_cidr != null ? null : data.azurerm_virtual_network.aks.id

  # Fallback: use the VNet associated with AKS
  depends_on = [azurerm_private_dns_zone.postgresql]
}

# ── Staging Instance ─────────────────────────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "staging" {
  name                   = "${var.cluster_name}-pg-staging"
  resource_group_name    = azurerm_resource_group.fabric.name
  location               = azurerm_resource_group.fabric.location
  version                = "16"
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password

  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768

  delegated_subnet_id = azurerm_subnet.postgresql.id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id

  zone = "1"

  tags = merge(var.tags, { environment = "staging" })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_postgresql_flexible_server_database" "staging" {
  name      = "fabric_staging"
  server_id = azurerm_postgresql_flexible_server.staging.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Production Instance ──────────────────────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "production" {
  name                   = "${var.cluster_name}-pg-production"
  resource_group_name    = azurerm_resource_group.fabric.name
  location               = azurerm_resource_group.fabric.location
  version                = "16"
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password

  sku_name   = "GP_Standard_D2s_v3"
  storage_mb = 65536

  delegated_subnet_id = azurerm_subnet.postgresql.id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id

  # Zone-redundant HA — per Section 7.1
  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  zone = "1"

  tags = merge(var.tags, { environment = "production" })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_postgresql_flexible_server_database" "production" {
  name      = "fabric_production"
  server_id = azurerm_postgresql_flexible_server.production.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Data source: AKS VNet ────────────────────────────────────────────────────
data "azurerm_virtual_network" "aks" {
  name                = "${var.cluster_name}-vnet"
  resource_group_name = azurerm_resource_group.fabric.name
}
