# Argo Rollouts — Progressive Delivery Controller
# Design Reference: Section 6.2 (Progressive Delivery Strategy)
# Task D-01: Blue-green for staging, canary for production
#
# Deployed via Helm to argo-rollouts namespace.
# Uses NGINX Ingress as traffic router.
# Prometheus metrics provider for analysis.

resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = "2.35.1"
  namespace  = "argo-rollouts"

  depends_on = [kubernetes_namespace.fabric["argo-rollouts"]]

  # Dashboard UI
  set {
    name  = "dashboard.enabled"
    value = "true"
  }

  set {
    name  = "dashboard.service.type"
    value = "ClusterIP"
  }

  # Controller config
  set {
    name  = "controller.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "256Mi"
  }

  # Metrics for Prometheus
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.serviceMonitor.namespace"
    value = "monitoring"
  }
}
