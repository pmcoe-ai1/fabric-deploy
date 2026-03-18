# External Secrets Operator — Vault-to-Kubernetes Secret Syncing
# Design Reference: Section 8.2 (External Secrets Operator Flow)
# Task E-03: Deploy ESO and configure SecretStores + ExternalSecrets
#
# Deployed via Helm to external-secrets namespace.
# Syncs secrets from HashiCorp Vault to Kubernetes Secrets every 15s.
#
# Defect 18 fix: Removed ClusterSecretStore (kubernetes_manifest) from Terraform.
# Replaced with namespace-scoped SecretStore YAMLs in overlays/staging/ and
# overlays/production/ — managed by Argo CD. This eliminates:
#   - The two-phase apply requirement (Defect 14)
#   - The ServiceAccount namespace mismatch
#   - The single-role-for-both-envs problem

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.13"
  namespace  = "external-secrets"

  depends_on = [kubernetes_namespace.fabric["external-secrets"]]

  # Controller config
  set {
    name  = "nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "webhook.nodeSelector.fabric/pool"
    value = "system"
  }

  set {
    name  = "certController.nodeSelector.fabric/pool"
    value = "system"
  }

  # Resource requests
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

  # Metrics
  set {
    name  = "serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "serviceMonitor.namespace"
    value = "monitoring"
  }
}
