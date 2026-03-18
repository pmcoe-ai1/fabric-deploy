# Grafana Loki — Log Aggregation
# Design Reference: Section 9.1 (Observability Stack)
# Task F-02: Deploy Loki for centralized log collection
#
# Deployed via Helm to monitoring namespace.
# Collects: application logs (stdout/stderr), Kubernetes events,
# Argo CD sync logs, Argo Rollouts analysis logs, Vault audit logs.
# Configured as Grafana data source for LogQL queries.

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.6.2"
  namespace  = "monitoring"

  depends_on = [
    kubernetes_namespace.fabric["monitoring"],
    helm_release.kube_prometheus_stack,
  ]

  timeout = 600
  wait    = false

  # Single-binary mode for simplicity (suitable for staging/small prod)
  set {
    name  = "deploymentMode"
    value = "SingleBinary"
  }

  set {
    name  = "singleBinary.replicas"
    value = "1"
  }

  # Disable simple scalable targets to avoid conflict with SingleBinary mode
  set {
    name  = "read.replicas"
    value = "0"
  }

  set {
    name  = "write.replicas"
    value = "0"
  }

  set {
    name  = "backend.replicas"
    value = "0"
  }

  set {
    name  = "singleBinary.nodeSelector.fabric/pool"
    value = "system"
  }

  # Storage — filesystem (upgrade to Azure Blob for durability in production)
  set {
    name  = "loki.storage.type"
    value = "filesystem"
  }

  set {
    name  = "singleBinary.persistence.enabled"
    value = "true"
  }

  set {
    name  = "singleBinary.persistence.size"
    value = "20Gi"
  }

  # Retention — 30 days default
  set {
    name  = "loki.commonConfig.replication_factor"
    value = "1"
  }

  set {
    name  = "loki.limits_config.retention_period"
    value = "720h"
  }

  # Schema config
  set {
    name  = "loki.schemaConfig.configs[0].from"
    value = "2024-01-01"
  }

  set {
    name  = "loki.schemaConfig.configs[0].store"
    value = "tsdb"
  }

  set {
    name  = "loki.schemaConfig.configs[0].object_store"
    value = "filesystem"
  }

  set {
    name  = "loki.schemaConfig.configs[0].schema"
    value = "v13"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.prefix"
    value = "index_"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.period"
    value = "24h"
  }

  # Disable gateway for single-binary mode
  set {
    name  = "gateway.enabled"
    value = "false"
  }

  # Resource requests
  set {
    name  = "singleBinary.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "singleBinary.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "singleBinary.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "singleBinary.resources.limits.memory"
    value = "512Mi"
  }

  # Disable test pods
  set {
    name  = "test.enabled"
    value = "false"
  }
}

# Promtail — DaemonSet log collector, ships logs to Loki
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.4"
  namespace  = "monitoring"

  depends_on = [
    kubernetes_namespace.fabric["monitoring"],
    helm_release.loki,
  ]

  timeout = 600
  wait    = false

  # Loki endpoint
  set {
    name  = "config.clients[0].url"
    value = "http://loki:3100/loki/api/v1/push"
  }

  # Collect from all namespaces
  set {
    name  = "config.snippets.scrapeConfigs"
    value = ""
  }

  # Resource requests (DaemonSet — runs on every node)
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }
}
