# Loki Operational Runbook

**Component:** Grafana Loki (log aggregation)
**Namespace:** `monitoring`
**Helm Chart:** `grafana/loki` v6.6.2 + `grafana/promtail` v6.16.4
**Design Reference:** Section 9.1 (Observability Stack)

---

## 1. Architecture Overview

- **Mode:** SingleBinary (single replica)
- **Storage:** Local PVC (20Gi) — upgrade to Azure Blob Storage for production durability
- **Log collector:** Promtail DaemonSet (runs on all nodes)
- **Retention:** 30 days (720h)
- **Data source:** Configured in Grafana for LogQL queries

## 2. Log Retention Policy

| Setting | Default | Location |
|---------|---------|----------|
| Retention period | 30 days (720h) | `terraform/loki.tf` — `loki.limits_config.retention_period` |
| Compaction | Automatic | Loki internal compactor |
| Storage limit | 20Gi PVC | `terraform/loki.tf` — `singleBinary.persistence.size` |

### Changing retention
```hcl
# In terraform/loki.tf:
set {
  name  = "loki.limits_config.retention_period"
  value = "360h"   # 15 days
}
```
Apply: `terraform apply -target=helm_release.loki`

## 3. Storage Backend Management

### Current: Local PVC
- Simple, suitable for staging
- Data lost if PVC is deleted
- Limited by Azure Disk size

### Recommended for Production: Azure Blob Storage
```hcl
# Replace filesystem config in terraform/loki.tf with:
set {
  name  = "loki.storage.type"
  value = "azure"
}
set {
  name  = "loki.storage.azure.accountName"
  value = "<storage-account>"
}
set {
  name  = "loki.storage.azure.accountKey"
  value = "<access-key>"  # Use Vault secret reference
}
set {
  name  = "loki.storage.azure.containerName"
  value = "loki-chunks"
}
```

## 4. Upgrading Loki

```bash
# 1. Check current version
helm list -n monitoring | grep loki

# 2. Update version in terraform/loki.tf
#    Change: version = "6.6.2" → version = "6.7.0"

# 3. Review changelog
#    https://github.com/grafana/loki/releases

# 4. Apply
terraform plan -target=helm_release.loki
terraform apply -target=helm_release.loki

# 5. Verify
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50
```

## 5. Handling Ingestion Lag / Backpressure

### Symptoms
- Alert: `LokiIngestionErrorRate`
- Logs delayed in Grafana
- Promtail logs show `429 Too Many Requests`

### Diagnosis
```bash
# Check Loki pod resource usage
kubectl top pod -n monitoring -l app.kubernetes.io/name=loki

# Check Promtail logs for errors
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=100

# Check Loki ingestion rate
# In Grafana: query `sum(rate(loki_distributor_lines_received_total[5m]))`
```

### Fixes
1. **Increase Loki resources** — update CPU/memory limits in `terraform/loki.tf`
2. **Scale Promtail** — if nodes are overloaded, check DaemonSet resource limits
3. **Reduce log volume** — add pipeline stages in Promtail to drop noisy logs
4. **Switch to microservices mode** — for high volume (>100GB/day), deploy Loki in distributed mode

## 6. Querying and Debugging Log Ingestion

### Verify logs are being ingested
```bash
# Port-forward to Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# Query recent logs
curl -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="staging"}' \
  --data-urlencode 'limit=10' | jq .
```

### Common LogQL queries in Grafana
```
# All logs from staging
{namespace="staging"}

# Error logs from FABRIC app
{namespace="staging", app="fabric"} |= "error"

# Argo CD sync logs
{namespace="argocd"} |= "sync"

# Vault audit logs
{namespace="vault"} | json | event_type="request"
```

## 7. Monitoring and Alerts

| Alert | Severity | Action |
|-------|----------|--------|
| `LokiIngestionErrorRate` | Warning | Check Loki resources; see Section 5 |
| `LokiStorageHigh` | Warning | Expand PVC or reduce retention |
| `PromtailNotRunning` | Warning | Check DaemonSet: `kubectl get ds -n monitoring promtail` |

PrometheusRule alerts defined in `kubernetes/monitoring/loki-alerts.yaml`.
