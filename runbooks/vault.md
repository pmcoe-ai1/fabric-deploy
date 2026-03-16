# Vault Operational Runbook

**Component:** HashiCorp Vault (self-hosted on AKS)
**Namespace:** `vault`
**Helm Chart:** `hashicorp/vault` v0.28.0
**Design Reference:** Section 10 (Secrets & Security), Decision #3

---

## 1. Architecture Overview

- **Mode:** HA with Raft integrated storage (3 replicas)
- **Auto-unseal:** Azure Key Vault (`fabric-aks-unseal` Key Vault, `vault-unseal-key` RSA key)
- **Auth:** Kubernetes auth method (pod service accounts)
- **Secrets engine:** KV v2 at `secret/`
- **Ingress:** `vault.fabric.internal` via NGINX Ingress

## 2. Auto-Unseal — How It Works

Vault uses Azure Key Vault for automatic unsealing:

1. On startup, each Vault pod contacts Azure Key Vault using the AKS managed identity
2. The unseal key is wrapped/unwrapped using the RSA key `vault-unseal-key`
3. No manual intervention required for normal restarts or pod rescheduling

**Key Vault resource:** `fabric-aks-unseal` in resource group `fabric-rg`
**Key name:** `vault-unseal-key` (RSA 2048)

## 3. Vault Sealed — Troubleshooting

If Vault is sealed (alert: `VaultSealed`):

### Check seal status
```bash
kubectl exec -n vault vault-0 -- vault status
```

### Common causes and fixes

| Cause | Fix |
|-------|-----|
| Azure Key Vault unavailable | Check Azure status page; verify Key Vault exists: `az keyvault show --name fabric-aks-unseal` |
| Managed identity permissions changed | Re-apply Terraform: `terraform apply -target=azurerm_key_vault_access_policy.vault_unseal` |
| Key deleted or disabled | Check key status: `az keyvault key show --vault-name fabric-aks-unseal --name vault-unseal-key` |
| Network policy blocking Key Vault | Check NSG rules allow outbound to Azure Key Vault endpoints |
| Pod crash loop | Check logs: `kubectl logs -n vault vault-0` |

### Manual unseal (emergency — if auto-unseal is broken)
```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Check status
VAULT_ADDR=http://localhost:8200 vault status

# If recovery keys are available (generated during init):
VAULT_ADDR=http://localhost:8200 vault operator unseal <recovery-key>
```

## 4. Root Token Rotation

```bash
# Generate a new root token using recovery keys
kubectl exec -n vault vault-0 -- vault operator generate-root -init
kubectl exec -n vault vault-0 -- vault operator generate-root -nonce=<nonce> <recovery-key>
kubectl exec -n vault vault-0 -- vault operator generate-root -nonce=<nonce> -decode=<encoded-token> -otp=<otp>

# Revoke old root token
VAULT_TOKEN=<new-root-token> vault token revoke <old-root-token>
```

**Schedule:** Rotate root token quarterly. Store securely — do NOT commit to Git.

## 5. Adding / Removing / Rotating Secrets

### Add a new secret
```bash
vault kv put secret/fabric/<env>/<name> key=value
```

### Read a secret
```bash
vault kv get secret/fabric/<env>/<name>
```

### Rotate a secret
```bash
# Write new version (KV v2 keeps history)
vault kv put secret/fabric/<env>/<name> key=new-value

# Verify
vault kv get secret/fabric/<env>/<name>

# Restart affected pods to pick up new secret (if using init container)
kubectl rollout restart deployment/fabric -n <env>
```

### Delete a secret
```bash
vault kv delete secret/fabric/<env>/<name>
```

## 6. Upgrading Vault

```bash
# 1. Check current version
kubectl exec -n vault vault-0 -- vault version

# 2. Update Helm chart version in terraform/vault.tf
#    Change: version = "0.28.0" → version = "0.29.0"

# 3. Plan and apply
cd terraform
terraform plan -target=helm_release.vault
terraform apply -target=helm_release.vault

# 4. Verify — pods restart one at a time (rolling update)
kubectl get pods -n vault -w

# 5. Check version and seal status
kubectl exec -n vault vault-0 -- vault status
```

## 7. Raft Snapshot and Restore

### Manual snapshot
```bash
kubectl exec -n vault vault-0 -- vault operator raft snapshot save /tmp/vault-snapshot.snap
kubectl cp vault/vault-0:/tmp/vault-snapshot.snap ./vault-snapshot-$(date +%Y%m%d).snap
```

### Automated snapshots
A CronJob runs daily at 02:00 UTC, saving snapshots to Azure Blob Storage.
See `kubernetes/vault/raft-snapshot-cronjob.yaml`.

### Restore from snapshot
```bash
# 1. Copy snapshot to Vault pod
kubectl cp ./vault-snapshot-YYYYMMDD.snap vault/vault-0:/tmp/restore.snap

# 2. Restore (WARNING: replaces all data)
kubectl exec -n vault vault-0 -- vault operator raft snapshot restore /tmp/restore.snap

# 3. Verify secrets are accessible
kubectl exec -n vault vault-0 -- vault kv get secret/fabric/staging/database
```

## 8. Monitoring and Alerts

| Alert | Severity | Action |
|-------|----------|--------|
| `VaultSealed` | Critical | See Section 3 — immediate action required |
| `VaultLeaderLost` | Warning | Check Raft cluster health: `vault operator raft list-peers` |
| `VaultStorageUsage > 80%` | Warning | Increase PVC size or clean old KV versions |
| `VaultAuditLogWriteFailure` | Critical | Check audit log backend; Vault will stop serving requests if audit fails |

PrometheusRule alerts are defined in `kubernetes/vault/vault-alerts.yaml`.
