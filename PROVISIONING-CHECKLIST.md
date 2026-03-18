# FABRIC Azure Infrastructure — Provisioning Checklist

All tasks required to go from zero to a running FABRIC platform on Azure.
Check each box only after verifying the step completed successfully.

---

## 1. Platform Service Logins

### External Platforms (accounts required before starting)

- [x] **Azure** — `az login` — subscription `2561d468-861d-49bb-a304-811fb1a5d20a`, tenant `95070d92-eb4b-4f5a-b94a-c63a4397c474`
- [x] **GitHub** — `gh auth login` — write access to `pmcoe-ai1/fabric-deploy` and `pmcoe-ai1/FABRIC`
- [x] **Anthropic** — API key "Fabric" exists (`sk-ant-api03-TVk...iwAA`) for Vault seeding
- [ ] **Domain Registrar** — login credentials for the domain backing `var.dns_zone_name` — needed for NS delegation
- [x] **Slack** — workspace `T0ALZ2VKQSZ`, FABRIC Alertmanager app with 3 incoming webhooks created
  - [x] Created channel `#info-alerts` (catch-all, replaces `#fabric-alerts`)
  - [x] Created channel `#critical-alerts` (replaces `#fabric-alerts-critical`)
  - [x] Created channel `#warning-alerts`
  - [x] Created incoming webhook for `#info-alerts` — `https://hooks.slack.com/services/T0ALZ2VKQSZ/B0AN39UG5UY/...`
  - [x] Created incoming webhook for `#critical-alerts` — `https://hooks.slack.com/services/T0ALZ2VKQSZ/B0ALTHLQG8P/...`
  - [x] Created incoming webhook for `#warning-alerts` — `https://hooks.slack.com/services/T0ALZ2VKQSZ/B0AM91GC1RQ/...`
- [x] **PagerDuty** — account at `pm-coe.pagerduty.com`, Events API v2 routing key `5e40313c69324e0ed0f152747cc1c5ef`

### Self-Hosted Services (accessed after deployment)

- [ ] **Vault** — root token obtained from `vault operator init` (post-deploy)
- [ ] **Argo CD** — initial admin password retrieved from cluster secret (post-deploy)
- [ ] **Grafana** — admin password set via Helm value / Vault (post-deploy)
- [ ] **AKS / kubectl** — `az aks get-credentials` (post-deploy)

---

## 2. Pre-Provisioning Setup

### Root .gitignore

A `.gitignore` exists at `terraform/.gitignore` covering `*.tfvars`, `*.tfstate*`, and `.terraform/`.
Add a root `.gitignore` as belt-and-suspenders protection:

- [ ] Create root `.gitignore`:
  ```
  # Terraform
  .terraform/
  *.tfstate*
  *.tfvars
  !terraform.tfvars.example

  # OS
  .DS_Store
  ```
- [ ] Commit

### Terraform State Backend

- [ ] Create resource group `fabric-tfstate-rg`
  ```bash
  az group create --name fabric-tfstate-rg --location australiaeast
  ```
- [ ] Create storage account `fabrictfstatepmcoe`
  ```bash
  az storage account create --name fabrictfstatepmcoe --resource-group fabric-tfstate-rg --location australiaeast --sku Standard_LRS
  ```
- [ ] Create blob container `tfstate`
  ```bash
  az storage container create --name tfstate --account-name fabrictfstatepmcoe
  ```

### Repo Preparation

- [ ] Clone `fabric-deploy` repo
  ```bash
  git clone git@github.com:pmcoe-ai1/fabric-deploy.git
  cd fabric-deploy
  ```
- [ ] Verify `backend.tf` matches the storage account created above
  - Resource group: `fabric-tfstate-rg` (NOT `fabric-rg-tfstate-rg`)
  - Storage account: `fabrictfstatepmcoe`
  - Container: `tfstate`

---

## 3. Terraform Defects (fix before first apply)

These defects exist in the current Terraform code and must be fixed before provisioning.

### Defect 13 — outputs.tf references non-existent resource

- [ ] Fix line 30: `azurerm_postgresql_flexible_server.fabric.fqdn` → `.staging.fqdn`
- [ ] Fix line 35: `azurerm_postgresql_flexible_server.fabric.administrator_login` → `.staging.administrator_login`
- [ ] Add production FQDN output:
  ```hcl
  output "postgresql_production_fqdn" {
    value       = azurerm_postgresql_flexible_server.production.fqdn
    description = "Production PostgreSQL Flexible Server FQDN"
  }
  ```
- [ ] Commit fix

### Defect 14 — ClusterSecretStore requires two-phase apply

- [ ] No code fix needed — operational procedure: run phase 1 targets first, then full apply (see Section 5)
- [ ] Root cause: ESO Helm chart registers the `ClusterSecretStore` CRD; `kubernetes_manifest` cannot plan against a CRD that does not exist yet

### Defect 15 — Kubernetes version outdated

- [ ] Change `variables.tf` default `kubernetes_version` from `1.29` to `1.32`
- [ ] Update `terraform/terraform.tfvars.example` line 8: `kubernetes_version` from `1.29` to `1.32`
- [ ] Commit fix

### Defect 16 — PostgreSQL VNet reference broken

`postgresql.tf` line 13 uses `virtual_network_name = azurerm_kubernetes_cluster.fabric.name` — this passes the AKS cluster name as a VNet name. AKS with Azure CNI creates its VNet in the `MC_*` resource group with an auto-generated name, not in `fabric-rg`.

`data.azurerm_virtual_network.aks` (line 109-112) looks for `${var.cluster_name}-vnet` in `fabric-rg` — this VNet does not exist.

Prescriptive fix — create an explicit VNet:

- [ ] Add to `aks.tf` (or new `network.tf`):
  ```hcl
  resource "azurerm_virtual_network" "fabric" {
    name                = "${var.cluster_name}-vnet"
    location            = azurerm_resource_group.fabric.location
    resource_group_name = azurerm_resource_group.fabric.name
    address_space       = ["10.0.0.0/8"]
    tags                = var.tags
  }

  resource "azurerm_subnet" "aks_nodes" {
    name                 = "aks-nodes"
    resource_group_name  = azurerm_resource_group.fabric.name
    virtual_network_name = azurerm_virtual_network.fabric.name
    address_prefixes     = ["10.0.0.0/16"]
  }
  ```
- [ ] Update AKS `default_node_pool` to use `vnet_subnet_id = azurerm_subnet.aks_nodes.id`
- [ ] Update `postgresql.tf` line 13: `virtual_network_name = azurerm_virtual_network.fabric.name`
- [ ] Update `data.azurerm_virtual_network.aks` to reference the explicit VNet, or remove it entirely (no longer needed)
- [ ] Update `azurerm_private_dns_zone_virtual_network_link.postgresql` to use `virtual_network_id = azurerm_virtual_network.fabric.id`
- [ ] Commit fix

### Defect 17 — VM size too small for system pool

- [ ] Change `variables.tf` default `system_node_vm_size` from `Standard_B2s` to `Standard_D2s_v3`
- [ ] Update `terraform/terraform.tfvars.example` line 10: `system_node_vm_size` from `Standard_B2s` to `Standard_D2s_v3`
- [ ] Commit fix

### Defect 18 — ClusterSecretStore auth chain broken (3 compounding issues)

This is worse than originally described. Three issues compound:

| Layer | Problem | Evidence |
|-------|---------|----------|
| Missing ServiceAccount | CSR references SA `fabric` in namespace `external-secrets` (`external-secrets.tf:96-99`) — nothing creates this SA. The `fabric` SAs only exist in staging and production (`overlays/*/rbac.yaml`). | `external-secrets.tf:98` |
| Namespace mismatch | Vault role `fabric-staging` is bound to SA `fabric` in namespace `staging` (`seed-vault-secrets.sh:125-126`), not `external-secrets`. Vault will reject the JWT. | `seed-vault-secrets.sh:126` |
| Single role for both envs | One ClusterSecretStore using role `fabric-staging`. Production ExternalSecrets read `secret/fabric/production/*` which requires `fabric-production` policy — but CSR authenticates with `fabric-staging` which can only read `secret/fabric/staging/*`. | `external-secrets.tf:95` |

Fix — replace single ClusterSecretStore with two namespace-scoped SecretStores:

- [ ] Delete `kubernetes_manifest.cluster_secret_store` from `external-secrets.tf`
- [ ] Create `overlays/staging/secret-store.yaml`:
  ```yaml
  apiVersion: external-secrets.io/v1beta1
  kind: SecretStore
  metadata:
    name: vault-backend
    namespace: staging
  spec:
    provider:
      vault:
        server: "http://vault.vault:8200"
        path: "secret"
        version: "v2"
        auth:
          kubernetes:
            mountPath: "kubernetes"
            role: "fabric-staging"
            serviceAccountRef:
              name: "fabric"
  ```
- [ ] Create `overlays/production/secret-store.yaml` (same, with `role: fabric-production`, `namespace: production`)
- [ ] Update both `overlays/*/external-secret.yaml` — change `kind: ClusterSecretStore` to `kind: SecretStore`
- [ ] Add `secret-store.yaml` to both `overlays/*/kustomization.yaml` resources
- [ ] Remove two-phase apply requirement (Defect 14 becomes moot — no more `kubernetes_manifest`)
- [ ] Commit fix

### Defect 19 — Vault auto-unseal missing tenant_id

`vault.tf:104-107` — the `seal "azurekeyvault"` stanza only sets `vault_name` and `key_name`. Even with managed identity, Vault requires `tenant_id` to know which Azure AD tenant to authenticate against. Without it, Vault pods will fail to unseal.

- [ ] Add `tenant_id` to the seal config in `vault.tf`:
  ```hcl
  seal "azurekeyvault" {
    vault_name = "${azurerm_key_vault.vault_unseal.name}"
    key_name   = "${azurerm_key_vault_key.vault_unseal.name}"
    tenant_id  = "${data.azurerm_client_config.current.tenant_id}"
  }
  ```
- [ ] Commit fix

### Defect 20 — No TLS certificates (no cert-manager)

All Ingress resources (Vault, Argo CD, Grafana) are exposed via NGINX Ingress but there is no cert-manager and no Certificate resources. All endpoints will serve self-signed or no TLS.

- [ ] Create `terraform/cert-manager.tf`:
  ```hcl
  resource "helm_release" "cert_manager" {
    name       = "cert-manager"
    repository = "https://charts.jetstack.io"
    chart      = "cert-manager"
    version    = "1.14.4"
    namespace  = "cert-manager"
    create_namespace = true

    set {
      name  = "installCRDs"
      value = "true"
    }

    set {
      name  = "nodeSelector.fabric/pool"
      value = "system"
    }

    depends_on = [azurerm_kubernetes_cluster.fabric]
  }
  ```
- [ ] Create a `ClusterIssuer` for Let's Encrypt (staging first, then production)
- [ ] Add `tls` blocks and `cert-manager.io/cluster-issuer` annotations to Ingress resources in `argocd.tf`, `vault.tf`, `monitoring.tf`
- [ ] Or: document that TLS is manual and operators must provide certs
- [ ] Commit fix

### Post-fix verification

- [ ] `terraform fmt -check` — no formatting issues
- [ ] `terraform validate` — syntax valid
- [ ] Commit and push all defect fixes

---

## 4. Create terraform.tfvars

- [ ] Create `terraform/terraform.tfvars` with actual values:
  ```hcl
  environment              = "staging"
  location                 = "australiaeast"
  resource_group_name      = "fabric-rg"
  cluster_name             = "fabric-aks"
  kubernetes_version       = "1.32"
  system_node_count        = 2
  system_node_vm_size      = "Standard_D2s_v3"
  app_node_count           = 2
  app_node_vm_size         = "Standard_B2s"
  postgresql_admin_username = "fabricadmin"
  postgresql_admin_password = "<SECURE_PASSWORD>"
  dns_zone_name            = "<YOUR_DOMAIN>"
  grafana_admin_password   = "<SECURE_PASSWORD>"
  ```
- [ ] Verify `terraform.tfvars` is in `.gitignore` (confirmed: `terraform/.gitignore` excludes `*.tfvars`)

---

## 5. Terraform Apply — Phase 1 (Azure resources + Helm charts)

Phase 1 creates everything. If Defect 18 is fixed (SecretStore replaces ClusterSecretStore), two-phase apply is no longer needed.

If the `kubernetes_manifest` resource is still present, exclude it with `-target` flags (see below).

- [ ] `terraform init`
- [ ] `terraform plan` — review output, confirm resource count
- [ ] `terraform apply` (or use `-target` to exclude `kubernetes_manifest` if still present):
  ```bash
  terraform apply \
    -target=azurerm_resource_group.fabric \
    -target=azurerm_virtual_network.fabric \
    -target=azurerm_subnet.aks_nodes \
    -target=azurerm_kubernetes_cluster.fabric \
    -target=azurerm_kubernetes_cluster_node_pool.app \
    -target=kubernetes_namespace.fabric \
    -target=azurerm_key_vault.vault_unseal \
    -target=azurerm_key_vault_access_policy.vault_unseal \
    -target=azurerm_key_vault_key.vault_unseal \
    -target=azurerm_subnet.postgresql \
    -target=azurerm_private_dns_zone.postgresql \
    -target=azurerm_private_dns_zone_virtual_network_link.postgresql \
    -target=azurerm_postgresql_flexible_server.staging \
    -target=azurerm_postgresql_flexible_server_database.staging \
    -target=azurerm_postgresql_flexible_server.production \
    -target=azurerm_postgresql_flexible_server_database.production \
    -target=helm_release.nginx_ingress \
    -target=helm_release.cert_manager \
    -target=helm_release.argocd \
    -target=helm_release.argo_rollouts \
    -target=helm_release.vault \
    -target=helm_release.external_secrets \
    -target=helm_release.kube_prometheus_stack \
    -target=helm_release.loki \
    -target=helm_release.promtail \
    -target=helm_release.tempo \
    -target=helm_release.otel_collector \
    -target=azurerm_dns_zone.fabric \
    -target=azurerm_dns_a_record.staging \
    -target=azurerm_dns_a_record.production \
    -target=azurerm_dns_a_record.argocd \
    -target=azurerm_dns_a_record.vault \
    -target=azurerm_dns_a_record.grafana
  ```
- [ ] Apply completes without errors

### Phase 1 Verification

- [ ] `az aks get-credentials --resource-group fabric-rg --name fabric-aks`
- [ ] `kubectl get nodes` — system and app pools visible
- [ ] `kubectl get ns` — all 8 namespaces exist (+ cert-manager if added)
- [ ] `kubectl -n argocd get pods` — Argo CD pods running
- [ ] `kubectl -n vault get pods` — 3 Vault pods running (may be Not Ready until initialized)
- [ ] `kubectl -n monitoring get pods` — Prometheus, Grafana, Alertmanager pods running
- [ ] `kubectl -n monitoring get pods -l app.kubernetes.io/name=loki` — Loki pod running
- [ ] `kubectl -n monitoring get ds -l app.kubernetes.io/name=promtail` — Promtail DaemonSet running on all nodes
- [ ] `kubectl -n monitoring get pods -l app.kubernetes.io/name=tempo` — Tempo pod running
- [ ] `kubectl -n monitoring get pods -l app.kubernetes.io/name=opentelemetry-collector` — OTel Collector running
- [ ] `kubectl -n ingress-nginx get svc` — LoadBalancer has external IP
- [ ] `kubectl -n external-secrets get pods` — ESO controller running
- [ ] `kubectl get crd rollouts.argoproj.io` — Argo Rollouts CRD registered
- [ ] `kubectl get crd analysistemplates.argoproj.io` — AnalysisTemplate CRD registered

---

## 6. Terraform Apply — Phase 2 (CRD-dependent resources)

> **Note:** If Defect 18 fix replaced `kubernetes_manifest.cluster_secret_store` with namespace-scoped SecretStore YAMLs in the overlays, this phase is no longer needed — skip to Section 7.

- [ ] `terraform plan` — should now show only `kubernetes_manifest.cluster_secret_store`
- [ ] `terraform apply` — creates the ClusterSecretStore
- [ ] Verify: `kubectl get clustersecretstore vault-backend` — shows `Valid` or `Ready`

---

## 7. DNS Delegation

- [ ] Run `terraform output dns_zone_name_servers` — note the 4 NS records
  (This output is defined in `dns.tf:79`, not `outputs.tf`)
- [ ] Log in to domain registrar
- [ ] Create NS records delegating `var.dns_zone_name` to the Azure DNS name servers
- [ ] Verify propagation:
  ```bash
  dig +short NS <your-domain>
  ```
- [ ] Verify Argo CD reachable: `curl -I https://argocd.<your-domain>` (should return 200/302, valid TLS if cert-manager is configured)
- [ ] Verify Grafana reachable: `curl -I https://grafana.<your-domain>`
- [ ] Verify Vault reachable: `curl -I https://vault.<your-domain>`
- [ ] If TLS is not yet configured (no cert-manager), use `curl -kI` and document as a follow-up

---

## 8. Vault Initialization, Unsealing, and HA Raft Join

- [ ] Port-forward to Vault (if DNS not yet propagated):
  ```bash
  kubectl -n vault port-forward svc/vault 8200:8200
  export VAULT_ADDR=http://127.0.0.1:8200
  ```
- [ ] Initialize Vault (on vault-0 only):
  ```bash
  kubectl -n vault exec vault-0 -- vault operator init
  ```
- [ ] **Save the recovery keys and root token securely** — these cannot be recovered
- [ ] Verify auto-unseal is working (Azure Key Vault):
  ```bash
  kubectl -n vault exec vault-0 -- vault status
  ```
  - `Sealed: false`
  - `Seal Type: azurekeyvault`
- [ ] **Join vault-1 and vault-2 to the Raft cluster:**
  ```bash
  kubectl -n vault exec vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
  kubectl -n vault exec vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
  ```
- [ ] Verify HA Raft cluster:
  ```bash
  kubectl -n vault exec vault-0 -- vault operator raft list-peers
  ```
  - All 3 nodes listed (vault-0 leader, vault-1 and vault-2 followers)
- [ ] Verify all 3 pods are Ready:
  ```bash
  kubectl -n vault get pods
  ```
- [ ] Export root token:
  ```bash
  export VAULT_TOKEN=<root-token>
  ```

---

## 9. Vault Secret Seeding

Use the existing `scripts/seed-vault-secrets.sh` script (covers KV engine, K8s auth, secrets, policies, and roles).

### Pre-seed: Fix K8s auth config for external execution

The seed script writes `kubernetes_host="https://kubernetes.default.svc:443"` which is correct for in-cluster use. When running from a local machine via port-forward, the K8s auth method also needs the cluster CA certificate and a service account token for token review.

- [ ] After running the seed script, patch the K8s auth config with the correct CA and host:
  ```bash
  # Get cluster CA cert
  kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/k8s-ca.pem

  # Get the Vault SA JWT (for token review)
  VAULT_SA_TOKEN=$(kubectl -n vault get secret vault-token -o jsonpath='{.data.token}' | base64 -d)

  # Reconfigure K8s auth with full details
  vault write auth/kubernetes/config \
    kubernetes_host="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')" \
    kubernetes_ca_cert=@/tmp/k8s-ca.pem \
    token_reviewer_jwt="${VAULT_SA_TOKEN}"
  ```

### Run seed script

- [ ] Gather required values:
  ```bash
  # From Terraform outputs
  STAGING_FQDN=$(terraform -chdir=terraform output -raw postgresql_fqdn)
  PRODUCTION_FQDN=$(terraform -chdir=terraform output -raw postgresql_production_fqdn)
  PG_PASSWORD="<the password from terraform.tfvars>"
  ```
- [ ] Set environment variables:
  ```bash
  export VAULT_ADDR=http://127.0.0.1:8200   # or https://vault.<domain>
  export VAULT_TOKEN=<root-token>
  export STAGING_DATABASE_URL="postgresql://fabricadmin:${PG_PASSWORD}@${STAGING_FQDN}:5432/fabric_staging?sslmode=require"
  export PRODUCTION_DATABASE_URL="postgresql://fabricadmin:${PG_PASSWORD}@${PRODUCTION_FQDN}:5432/fabric_production?sslmode=require"
  export ANTHROPIC_API_KEY="sk-ant-..."
  export GRAFANA_ADMIN_PASSWORD="<same as terraform.tfvars>"
  ```
- [ ] Run the seed script:
  ```bash
  ./scripts/seed-vault-secrets.sh
  ```
- [ ] Verify secrets written:
  - [ ] `vault kv get secret/fabric/staging/database`
  - [ ] `vault kv get secret/fabric/production/database`
  - [ ] `vault kv get secret/fabric/shared/anthropic`
  - [ ] `vault kv get secret/fabric/shared/grafana`
- [ ] Verify policies created:
  - [ ] `vault policy read fabric-staging`
  - [ ] `vault policy read fabric-production`
- [ ] Verify K8s auth roles:
  - [ ] `vault read auth/kubernetes/role/fabric-staging`
  - [ ] `vault read auth/kubernetes/role/fabric-production`
- [ ] Apply the K8s auth config patch (see above)

---

## 10. Argo CD — Repository Credentials and Access

- [ ] Retrieve initial admin password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  ```
- [ ] Log in to Argo CD CLI:
  ```bash
  argocd login argocd.<your-domain> --username admin --password <password>
  ```
- [ ] **Add fabric-deploy repo credentials** (required if private repo):
  ```bash
  argocd repo add https://github.com/pmcoe-ai1/fabric-deploy.git \
    --username <github-username> \
    --password <github-pat-or-deploy-key>
  ```
  Or via SSH:
  ```bash
  argocd repo add git@github.com:pmcoe-ai1/fabric-deploy.git \
    --ssh-private-key-path ~/.ssh/id_ed25519
  ```
- [ ] Verify repo connection: `argocd repo list` — shows `Connected`
- [ ] Apply Argo CD Applications:
  ```bash
  kubectl apply -f argocd-apps/staging.yaml
  kubectl apply -f argocd-apps/production.yaml
  kubectl apply -f argocd-apps/infrastructure.yaml
  ```
- [ ] Verify Applications syncing:
  - [ ] `argocd app get fabric-staging` — `Synced`, `Healthy`
  - [ ] `argocd app get fabric-production` — `Synced`, `Healthy`
  - [ ] `argocd app get fabric-infrastructure` — `Synced`, `Healthy`

---

## 11. Alertmanager — Replace Notification Placeholders

- [x] Edit `infrastructure/monitoring/alertmanager-config.yaml`
- [x] Replace Slack webhook URLs (3 receivers updated with real webhook URLs):
  - [x] `default` receiver — `#info-alerts` webhook (`T0ALZ2VKQSZ/B0AN39UG5UY/...`)
  - [x] `slack-critical` receiver — `#critical-alerts` webhook (`T0ALZ2VKQSZ/B0ALTHLQG8P/...`)
  - [x] `slack-warning` receiver — `#warning-alerts` webhook (`T0ALZ2VKQSZ/B0AM91GC1RQ/...`)
- [x] Replace PagerDuty integration key — Events API v2 routing key `5e40313c69324e0ed0f152747cc1c5ef`
- [ ] Commit and push — Argo CD `fabric-infrastructure` Application will sync the change
- [ ] Verify alert delivery:
  ```bash
  # Fire a test alert
  kubectl -n monitoring exec -it prometheus-kube-prometheus-stack-prometheus-0 -- \
    amtool alert add test severity=warning --alertmanager.url=http://localhost:9093
  ```
- [ ] Confirm test alert received in `#warning-alerts`

---

## 12. Grafana — Verify Access and Dashboards

- [ ] Log in to `https://grafana.<your-domain>` with admin / `<grafana_admin_password>`
- [ ] Verify Prometheus data source is auto-configured
- [ ] Verify 4 FABRIC dashboards loaded (from infrastructure/ ConfigMaps):
  - [ ] Pipeline Health
  - [ ] Runtime Health
  - [ ] Deployment Status
  - [ ] Infrastructure Health
- [ ] Verify Loki data source is configured — test with `{namespace="monitoring"}`
- [ ] Verify Tempo data source is configured — test trace search

---

## 13. Kustomize Overlay Verification

- [ ] Verify staging overlay builds cleanly:
  ```bash
  kustomize build overlays/staging/
  ```
  - [ ] All resources have `namespace: staging`
  - [ ] Rollout resource present (not Deployment)
  - [ ] ExternalSecret references `kind: SecretStore` (not ClusterSecretStore, if Defect 18 is fixed)
  - [ ] SecretStore, NetworkPolicy, RBAC present
- [ ] Verify production overlay builds cleanly:
  ```bash
  kustomize build overlays/production/
  ```
  - [ ] All resources have `namespace: production`
  - [ ] Rollout resource present with canary strategy
  - [ ] Production resource limits applied (2 replicas, 250m CPU, 512Mi memory)

---

## 14. Container Image Pull Access

- [ ] Create imagePullSecret in staging namespace for ghcr.io:
  ```bash
  kubectl -n staging create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=<github-username> \
    --docker-password=<github-pat-with-read-packages>
  ```
- [ ] Create imagePullSecret in production namespace:
  ```bash
  kubectl -n production create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=<github-username> \
    --docker-password=<github-pat-with-read-packages>
  ```
- [ ] Or: configure the `fabric` ServiceAccount in each namespace with `imagePullSecrets`
- [ ] Or: if using a public ghcr.io package, skip this section

---

## 15. End-to-End Smoke Test

- [ ] ExternalSecrets are syncing:
  ```bash
  kubectl -n staging get externalsecret -o wide   # STATUS: SecretSynced
  kubectl -n production get externalsecret -o wide # STATUS: SecretSynced
  ```
- [ ] Kubernetes Secrets created from Vault (target name is `fabric-secrets`, not `database-credentials`):
  ```bash
  kubectl -n staging get secret fabric-secrets      # exists
  kubectl -n production get secret fabric-secrets    # exists
  ```
- [ ] NetworkPolicies active:
  ```bash
  kubectl -n staging get networkpolicy
  kubectl -n production get networkpolicy
  ```
- [ ] Prometheus scraping targets:
  - [ ] Access `https://grafana.<domain>` — Explore — Prometheus — `up` query returns targets
- [ ] Argo CD sync waves working (when an actual app image is pushed):
  - [ ] Wave 0: ConfigMaps/Secrets created
  - [ ] Wave 3: Rollout created
- [ ] Vault auto-unseal surviving pod restart:
  ```bash
  kubectl -n vault delete pod vault-0
  # Wait for pod to restart
  vault status   # Sealed: false
  ```
- [ ] Vault Raft snapshot CronJob deployed and scheduled:
  ```bash
  kubectl -n vault get cronjob
  ```
- [ ] Argo Rollouts controller ready:
  ```bash
  kubectl -n argo-rollouts get pods
  kubectl get crd rollouts.argoproj.io   # CRD exists
  ```

---

## 16. CI Pipeline Integration (FABRIC repo)

- [ ] GitHub Actions secrets configured in `pmcoe-ai1/FABRIC`:
  - [ ] `AZURE_CREDENTIALS` — service principal JSON for AKS access
  - [ ] `KUBECONFIG` or OIDC federation for kubectl access
- [ ] Container image builds push to `ghcr.io/pmcoe-ai1/fabric`
- [ ] CI workflow updates image tag in fabric-deploy overlays — Argo CD detects and syncs

---

## 17. Post-Provisioning Considerations

### ExternalSecret refresh interval

Both staging and production ExternalSecrets refresh every 15 seconds. For production this generates significant Vault API traffic. Consider changing:

- [ ] Staging: `refreshInterval: 1m`
- [ ] Production: `refreshInterval: 5m`

### Rollback Guidance

If provisioning fails partway through:

| Failure Point | Recovery |
|---------------|----------|
| `terraform apply` Phase 1 partial | `terraform plan` to see remaining resources, re-run `terraform apply` — Terraform is idempotent |
| `vault operator init` fails | Check pod logs (`kubectl -n vault logs vault-0`), verify Azure Key Vault access policy, verify `tenant_id` in seal config |
| DNS delegation breaks existing services | Remove the NS records at registrar, wait for TTL to expire |
| Argo CD sync fails | `argocd app get <app> --show-operation`, check repo credentials, verify Kustomize builds locally |
| ExternalSecret stuck `SecretSyncedError` | Check SecretStore status (`kubectl -n staging get secretstore vault-backend -o yaml`), verify Vault role bindings |
| Helm release stuck | `helm -n <namespace> list`, `helm -n <namespace> history <release>`, `helm -n <namespace> rollback <release> <revision>` |

### Terraform state lock

If `terraform apply` is interrupted and the state is locked:
```bash
terraform force-unlock <lock-id>
```

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| 1. Platform Logins | 10 services | DONE — 5/6 external (Domain Registrar pending), 4/4 self-hosted |
| 2. Pre-Provisioning | .gitignore + TF state backend + repo | DONE |
| 3. Defect Fixes | 8 defects in Terraform (13–20) | DONE — all 7 actionable fixed, Defect 20 deferred |
| 4. terraform.tfvars | Variable values | DONE |
| 5. TF Phase 1 | Azure + all Helm resources | DONE — AKS, PostgreSQL x2, 11 Helm releases, 5 DNS records |
| 6. TF Phase 2 | ClusterSecretStore (skip if Defect 18 fixed) | SKIPPED — Defect 18 fix eliminated need |
| 7. DNS Delegation | NS records at registrar | ☐ — needs domain registrar access |
| 8. Vault Init | Initialize + unseal + HA Raft join | DONE — auto-unseal working, 2-node Raft cluster |
| 9. Vault Seeding | Secrets, policies, roles + K8s auth patch | DONE — 4 secrets, 2 policies, 2 roles |
| 10. Argo CD | Repo creds + Applications | ☐ |
| 11. Alertmanager | Replace placeholders | DONE — webhooks + PagerDuty key replaced |
| 12. Grafana | Verify dashboards + Loki + Tempo | ☐ |
| 13. Kustomize | Overlay verification | ☐ |
| 14. Image Pull | ghcr.io imagePullSecrets | ☐ |
| 15. Smoke Test | End-to-end verification | ☐ |
| 16. CI Integration | GitHub Actions — AKS | ☐ |
| 17. Post-Provisioning | Refresh intervals, rollback docs | ☐ |
