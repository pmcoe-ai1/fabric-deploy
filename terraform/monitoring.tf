# Prometheus + Grafana — Observability Stack
# Design Reference: Section 11 (Observability & Monitoring)
# Decision #5: kube-prometheus-stack for metrics, alerting, and dashboards
#
# Deployed via Helm to monitoring namespace.
# Includes: Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics.
# ServiceMonitors from other components (NGINX, Argo CD, Vault) scrape into this.

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.2.2"
  namespace  = "monitoring"

  depends_on = [kubernetes_namespace.fabric["monitoring"]]

  # Prometheus configuration
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "50Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.cpu"
    value = "1"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "2Gi"
  }

  # Enable ServiceMonitor and PrometheusRule auto-discovery across all namespaces
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues"
    value = "false"
  }

  # Grafana configuration
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "grafana.ingress.enabled"
    value = "true"
  }

  set {
    name  = "grafana.ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "grafana.ingress.hosts[0]"
    value = "grafana.${var.dns_zone_name}"
  }

  set {
    name  = "grafana.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "grafana.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "grafana.resources.limits.memory"
    value = "256Mi"
  }

  # Grafana persistent storage
  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = "10Gi"
  }

  # Alertmanager configuration
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage"
    value = "5Gi"
  }

  # Node exporter — runs on all nodes
  set {
    name  = "nodeExporter.enabled"
    value = "true"
  }

  # kube-state-metrics
  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  set {
    name  = "kube-state-metrics.nodeSelector.fabric/pool"
    value = "system"
  }
}
