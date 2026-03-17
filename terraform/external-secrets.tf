# External Secrets Operator — Vault-to-Kubernetes Secret Syncing
# Design Reference: Section 8.2 (External Secrets Operator Flow)
# Task E-03: Deploy ESO and configure ClusterSecretStore + ExternalSecrets
#
# Deployed via Helm to external-secrets namespace.
# Syncs secrets from HashiCorp Vault to Kubernetes Secrets every 15s.

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

# ClusterSecretStore — Vault Backend
# Design Reference: Section 8.2 (External Secrets Operator Flow)
# Points to internal Vault cluster address via Kubernetes auth.
# Managed in Terraform because it's a cluster-scoped CRD that depends on
# both ESO and Vault being deployed first.
resource "kubernetes_manifest" "cluster_secret_store" {
  depends_on = [
    helm_release.external_secrets,
    helm_release.vault
  ]

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "vault-backend"
      labels = {
        "app.kubernetes.io/part-of" = "fabric"
      }
    }
    spec = {
      provider = {
        vault = {
          server  = "http://vault.vault:8200"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "fabric-staging"
              serviceAccountRef = {
                name      = "fabric"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }
}
