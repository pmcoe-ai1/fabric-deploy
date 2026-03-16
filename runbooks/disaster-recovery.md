# Disaster Recovery Runbook

**Scope:** Complete FABRIC platform recovery procedures
**Design Reference:** Section 13 (Disaster Recovery)

---

## 1. Recovery Time Objectives (RTO)

| Component | RTO | Data Loss Tolerance | Recovery Method |
|-----------|-----|---------------------|-----------------|
| AKS Cluster | 30 min | None (stateless) | Terraform re-apply |
| PostgreSQL | 15 min | Up to 5 min (PITR) | Azure automatic failover / point-in-time restore |
| Vault | 30 min | Last daily snapshot | Raft snapshot restore from Azure Blob |
| Argo CD | 10 min | None (config in Git) | Terraform re-apply + Git re-sync |
| Prometheus | 15 min | Acceptable (rebuilt) | Helm re-deploy; metrics rebuilt from scraping |
| Loki | 15 min | Acceptable (informational) | Helm re-deploy; historical logs lost |
| Tempo | 15 min | Acceptable (informational) | Helm re-deploy; historical traces lost |
| Application | 5 min | None (stateless) | Argo CD auto-sync from fabric-deploy |

---

## 2. AKS Cluster Failure

### Complete cluster loss

```bash
# 1. Re-provision cluster from Terraform state
cd terraform
terraform plan
terraform apply

# 2. Verify cluster is healthy
kubectl get nodes
kubectl get namespaces

# 3. Argo CD will auto-sync all applications from fabric-deploy
#    Wait for all ArgoCD applications to become Healthy
kubectl get applications -n argocd
```

### Partial node failure
```bash
# AKS auto-heals failed nodes. Check status:
kubectl get nodes
kubectl describe node <failed-node>

# If node is NotReady for >10 minutes, AKS will replace it
# Pods will be rescheduled automatically
```

---

## 3. PostgreSQL Failure

### Production: Automatic failover (zone-redundant HA)
- Azure automatically fails over to standby in zone 2
- Connection string remains the same (DNS-based)
- Downtime: typically <30 seconds

### Verify failover
```bash
az postgres flexible-server show \
  --resource-group fabric-rg \
  --name fabric-postgresql \
  --query "{state: state, haState: highAvailability.state}"
```

### Point-in-time restore (data corruption/accidental deletion)
```bash
# 1. Identify the restore point (up to 35 days back)
RESTORE_TIME="2024-03-15T10:30:00Z"

# 2. Create a new server from point-in-time
az postgres flexible-server restore \
  --resource-group fabric-rg \
  --name fabric-postgresql-restored \
  --source-server fabric-postgresql \
  --restore-time "${RESTORE_TIME}"

# 3. Verify restored data
psql "host=fabric-postgresql-restored.postgres.database.azure.com dbname=fabric_production user=fabricadmin" \
  -c "SELECT count(*) FROM orders;"

# 4. If data is correct, update DNS/connection string to point to restored server
#    Update Vault secret: secret/fabric/production/database

# 5. Delete old server after verification
```

### Staging: No HA (single zone)
```bash
# If staging PostgreSQL fails, re-provision:
terraform apply -target=azurerm_postgresql_flexible_server.fabric
terraform apply -target=azurerm_postgresql_flexible_server_database.staging
```

---

## 4. Vault Data Loss

### Restore from Raft snapshot

```bash
# 1. List available snapshots in Azure Blob Storage
az storage blob list \
  --account-name fabrictfstate \
  --container-name vault-snapshots \
  --output table

# 2. Download the most recent snapshot
az storage blob download \
  --account-name fabrictfstate \
  --container-name vault-snapshots \
  --name vault-snapshot-YYYYMMDD-HHMMSS.snap \
  --file /tmp/vault-restore.snap

# 3. Copy snapshot to Vault pod
kubectl cp /tmp/vault-restore.snap vault/vault-0:/tmp/restore.snap

# 4. Restore (WARNING: replaces ALL Vault data)
kubectl exec -n vault vault-0 -- \
  vault operator raft snapshot restore /tmp/restore.snap

# 5. Verify secrets are accessible
kubectl exec -n vault vault-0 -- \
  vault kv get secret/fabric/staging/database
kubectl exec -n vault vault-0 -- \
  vault kv get secret/fabric/production/database
```

### Complete Vault loss (no snapshot)
```bash
# 1. Re-deploy Vault via Terraform
terraform apply -target=helm_release.vault

# 2. Initialize Vault (generates new recovery keys)
kubectl exec -n vault vault-0 -- vault operator init

# 3. Re-seed all secrets
./scripts/seed-vault-secrets.sh

# 4. Restart application pods to pick up new Vault auth
kubectl rollout restart deployment/fabric -n staging
kubectl rollout restart deployment/fabric -n production
```

---

## 5. Prometheus Data Loss

Prometheus data loss is acceptable — metrics are rebuilt from scraping.

```bash
# Re-deploy Prometheus
terraform apply -target=helm_release.kube_prometheus_stack

# Verify targets are being scraped
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Historical data (up to retention period) will be rebuilt over time
# Dashboards will show gaps for the lost period
```

---

## 6. Loki / Tempo Data Loss

Log and trace data loss is acceptable — both are informational, not transactional.

```bash
# Re-deploy Loki
terraform apply -target=helm_release.loki -target=helm_release.promtail

# Re-deploy Tempo
terraform apply -target=helm_release.tempo -target=helm_release.otel_collector

# New logs/traces will begin collecting immediately
# Historical data is lost — this is acceptable per design
```

---

## 7. Complete Environment Rebuild from Scratch

Total time estimate: ~45 minutes

```bash
# 1. Provision all infrastructure (AKS, PostgreSQL, DNS)
cd terraform
terraform init
terraform apply

# 2. Verify cluster
kubectl get nodes
kubectl get namespaces

# 3. Argo CD deploys automatically via Helm
#    Wait for Argo CD to be healthy
kubectl get pods -n argocd

# 4. Apply Argo CD applications
kubectl apply -f argocd-apps/staging.yaml
kubectl apply -f argocd-apps/production.yaml

# 5. Initialize Vault
kubectl exec -n vault vault-0 -- vault operator init
./scripts/seed-vault-secrets.sh

# 6. Apply RBAC and Network Policies
kubectl apply -f kubernetes/rbac/
kubectl apply -f kubernetes/network-policies/

# 7. Apply monitoring extras
kubectl apply -f kubernetes/monitoring/
kubectl apply -f kubernetes/dashboards/

# 8. Restore PostgreSQL data (if available)
#    Use point-in-time restore or backup restore

# 9. Restore Vault data (if snapshot available)
#    See Section 4

# 10. Verify all applications
kubectl get applications -n argocd
kubectl get rollouts -n staging
curl https://staging.fabric.internal/healthz
```

---

## 8. Recovery Testing Schedule

| Test | Frequency | Procedure |
|------|-----------|-----------|
| PostgreSQL failover | Quarterly | Trigger manual failover in Azure Portal |
| Vault snapshot restore | Quarterly | Restore to a test namespace |
| Terraform rebuild | Bi-annually | Destroy and rebuild staging from scratch |
| Argo CD re-sync | Monthly | Delete an Argo CD app and verify re-sync |
| Application rollback | Monthly | Trigger rollback via Argo Rollouts |

---

## 9. Escalation Contacts

| Severity | Response | Contact |
|----------|----------|---------|
| Critical (production down) | Immediate | On-call via PagerDuty |
| High (degraded service) | 30 min | #fabric-alerts-critical Slack |
| Medium (component failure) | 2 hours | #fabric-alerts Slack |
| Low (monitoring gap) | Next business day | #fabric-ops Slack |
