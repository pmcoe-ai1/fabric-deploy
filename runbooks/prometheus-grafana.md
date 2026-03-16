# Prometheus & Grafana Operational Runbook

**Components:** Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics
**Namespace:** `monitoring`
**Helm Chart:** `prometheus-community/kube-prometheus-stack` v58.2.2
**Design Reference:** Section 11 (Observability & Monitoring)

---

## 1. Architecture Overview

- **Prometheus:** Metrics collection, alerting rules, 15-day retention
- **Grafana:** Dashboards, data source for Prometheus/Loki/Tempo
- **Alertmanager:** Alert routing and notification
- **node-exporter:** Node-level metrics (DaemonSet)
- **kube-state-metrics:** Kubernetes object metrics

All components run on the `system` node pool.

## 2. Data Retention Policy

| Component | Default Retention | How to Change |
|-----------|-------------------|---------------|
| Prometheus | 15 days | Update `prometheus.prometheusSpec.retention` in `terraform/monitoring.tf` |
| Grafana | Persistent (Azure Disk PVC) | N/A — dashboards are in Git via ConfigMaps |
| Alertmanager | 120h (5 days) | Update `alertmanager.alertmanagerSpec.retention` |

### Changing retention
```hcl
# In terraform/monitoring.tf, update:
set {
  name  = "prometheus.prometheusSpec.retention"
  value = "30d"   # Change from 15d to 30d
}
```
Then apply: `terraform apply -target=helm_release.kube_prometheus_stack`

## 3. Disk Full — PVC Expansion

### Symptoms
- Alert: `PrometheusStorageDiskUsageHigh`
- Prometheus stops ingesting or crashes

### Fix: Expand PVC on Azure
```bash
# 1. Check current PVC size
kubectl get pvc -n monitoring

# 2. Edit PVC (Azure Disk supports online expansion)
kubectl patch pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring \
  --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# 3. Verify expansion
kubectl get pvc -n monitoring -w
```

### Alternative: Reduce retention
If disk expansion is not possible, reduce retention period (see Section 2).

## 4. Upgrading kube-prometheus-stack

```bash
# 1. Check current version
helm list -n monitoring

# 2. Update version in terraform/monitoring.tf
#    Change: version = "58.2.2" → version = "59.0.0"

# 3. Review upgrade notes
#    https://github.com/prometheus-community/helm-charts/releases

# 4. Plan and apply
cd terraform
terraform plan -target=helm_release.kube_prometheus_stack
terraform apply -target=helm_release.kube_prometheus_stack

# 5. Verify all pods healthy
kubectl get pods -n monitoring

# 6. Verify Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

**Warning:** Major version upgrades may include CRD changes. Check release notes for breaking changes. Apply CRD updates manually if needed:
```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.73.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
```

## 5. Grafana Backup Strategy

| Data | Backup Method |
|------|---------------|
| Dashboard JSON | In Git via fabric-deploy ConfigMaps (F-05) |
| Data sources | Provisioned via Helm values (terraform/monitoring.tf) |
| Grafana SQLite DB | Azure Disk PVC — backed up with Velero or az disk snapshot |
| User preferences | Stored in SQLite — included in PVC backup |

### Manual Grafana DB backup
```bash
kubectl cp monitoring/$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}'):/var/lib/grafana/grafana.db ./grafana-backup-$(date +%Y%m%d).db
```

## 6. Adding New Prometheus Scrape Targets

### Via ServiceMonitor (preferred)
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-service
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - staging
  selector:
    matchLabels:
      app: my-service
  endpoints:
    - port: metrics
      interval: 30s
```

### Via PodMonitor
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-pod
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: my-pod
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
```

**Important:** ServiceMonitor/PodMonitor must have `release: kube-prometheus-stack` label for auto-discovery (configured via `serviceMonitorSelectorNilUsesHelmValues: false`).

## 7. Adding New Alert Rules

Create a PrometheusRule resource:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: my-alerts
      rules:
        - alert: HighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High 5xx error rate"
```

## 8. Monitoring and Self-Monitoring Alerts

| Alert | Severity | Action |
|-------|----------|--------|
| `PrometheusTargetDown` | Warning | Check target pod health; verify ServiceMonitor labels |
| `PrometheusTSDBCompactionsFailing` | Warning | Check disk space; review Prometheus logs |
| `PrometheusStorageDiskUsageHigh` | Warning | Expand PVC (Section 3) or reduce retention |
| `AlertmanagerNotificationFailed` | Critical | Check Alertmanager config; verify notification channel (Slack, email) |

PrometheusRule alerts are defined in `kubernetes/monitoring/prometheus-self-alerts.yaml`.
