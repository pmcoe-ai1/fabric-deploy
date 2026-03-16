# NGINX Ingress Controller
# Design Reference: Section 7.1 (Infrastructure Components)
# Decision #10: NGINX Ingress Controller for canary traffic management
#
# Deployed via Helm to ingress-nginx namespace.
# Azure Load Balancer provisioned automatically by the Service (type: LoadBalancer).
# Configured with Argo Rollouts canary annotations support.

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.0"
  namespace  = "ingress-nginx"

  depends_on = [kubernetes_namespace.fabric["ingress-nginx"]]

  # Controller configuration
  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.nodeSelector.fabric/pool"
    value = "system"
  }

  # Enable Argo Rollouts canary annotations — required for Phase D
  set {
    name  = "controller.config.enable-snippets"
    value = "false"
  }

  # Metrics for Prometheus scraping
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

  # Azure Load Balancer annotations
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  # TLS default certificate (cert-manager will manage actual certs)
  set {
    name  = "controller.extraArgs.default-ssl-certificate"
    value = ""
  }

  # Resource limits for system pool
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
}
