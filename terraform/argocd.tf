# Argo CD — GitOps Continuous Delivery
# Design Reference: Section 6.1 (Argo CD Configuration)
#
# Deployed via Helm to argocd namespace.
# Watches the fabric-deploy repo for Kustomize overlay changes.
# Two Applications: staging and production (created in C-03).

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = "argocd"

  depends_on = [kubernetes_namespace.fabric["argocd"]]

  # Server configuration
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Expose via NGINX Ingress (configured after B-03)
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "server.ingress.hosts[0]"
    value = "argocd.${var.dns_zone_name}"
  }

  # Node selector — system pool
  set {
    name  = "controller.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "server.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "repoServer.nodeSelector.fabric/pool"
    value = "system"
  }

  # Resource limits
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "repoServer.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = "128Mi"
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

  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  set {
    name  = "server.metrics.serviceMonitor.enabled"
    value = "true"
  }
}
