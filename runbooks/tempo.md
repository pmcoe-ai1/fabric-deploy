# Tempo Operational Runbook

**Component:** Grafana Tempo (distributed tracing)
**Namespace:** `monitoring`
**Helm Chart:** `grafana/tempo` v1.10.1
**Design Reference:** Section 9.1 (Observability Stack)

---

## 1. Architecture Overview

- **Mode:** Single-binary
- **Storage:** Local PVC (10Gi) — upgrade to Azure Blob Storage for production
- **Trace ingestion:** OpenTelemetry Collector (deployment mode, 1 replica)
- **Retention:** 7 days (168h)
- **Protocols:** OTLP gRPC (4317) + OTLP HTTP (4318)
- **Data source:** Configured in Grafana with Loki correlation

## 2. Trace Retention Policy

| Setting | Default | Location |
|---------|---------|----------|
| Retention period | 7 days (168h) | `terraform/tempo.tf` — `tempo.retention` |
| Storage limit | 10Gi PVC | `terraform/tempo.tf` — `persistence.size` |

### Changing retention
```hcl
# In terraform/tempo.tf:
set {
  name  = "tempo.retention"
  value = "336h"   # 14 days
}
```
Apply: `terraform apply -target=helm_release.tempo`

## 3. Storage Backend Management

### Current: Local PVC
- Simple, suitable for staging
- 10Gi — adequate for low trace volume

### Production: Azure Blob Storage
```hcl
set {
  name  = "tempo.storage.trace.backend"
  value = "azure"
}
set {
  name  = "tempo.storage.trace.azure.container_name"
  value = "tempo-traces"
}
set {
  name  = "tempo.storage.trace.azure.storage_account_name"
  value = "<account>"
}
set {
  name  = "tempo.storage.trace.azure.storage_account_key"
  value = "<key>"  # Use Vault
}
```

## 4. Upgrading Tempo

```bash
# 1. Check current version
helm list -n monitoring | grep tempo

# 2. Update in terraform/tempo.tf
#    version = "1.10.1" → "1.11.0"

# 3. Review changelog
#    https://github.com/grafana/tempo/releases

# 4. Apply
terraform plan -target=helm_release.tempo
terraform apply -target=helm_release.tempo

# 5. Verify
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
```

## 5. Debugging Missing Traces

### Check trace pipeline end-to-end

```bash
# 1. Verify OTel Collector is receiving traces
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --tail=50

# 2. Verify Tempo is receiving from collector
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=50

# 3. Check Tempo ingestion metrics in Grafana
#    Query: sum(rate(tempo_distributor_spans_received_total[5m]))
#    If 0 → traces not reaching Tempo

# 4. Test trace ingestion manually
kubectl port-forward -n monitoring svc/otel-collector-opentelemetry-collector 4318:4318
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"test"}}]},"scopeSpans":[{"spans":[{"traceId":"00000000000000000000000000000001","spanId":"0000000000000001","name":"test-span","startTimeUnixNano":"1700000000000000000","endTimeUnixNano":"1700000001000000000"}]}]}]}'
```

### Common issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No traces at all | App not instrumented with OTel SDK | Add `@opentelemetry/sdk-node` to app |
| Traces appear then vanish | Retention too short | Increase `tempo.retention` |
| Partial traces | Collector dropping spans | Check collector resource limits |
| Trace-to-log link broken | Tempo data source not configured | Add Tempo data source in Grafana with Loki correlation |

## 6. Trace-to-Log Correlation

Tempo and Loki are linked in Grafana:
- Traces include a `traceID` field
- Loki logs include `traceID` when OTel context propagation is enabled
- In Grafana: click a trace span → "Logs for this span" queries Loki with the traceID

### Configure in Grafana data source
```json
{
  "tracesToLogs": {
    "datasourceUid": "<loki-uid>",
    "filterByTraceID": true,
    "spanStartTimeShift": "-1h",
    "spanEndTimeShift": "1h"
  }
}
```

## 7. Monitoring and Alerts

| Alert | Severity | Action |
|-------|----------|--------|
| `TempoIngestionErrorRate` | Warning | Check OTel Collector and Tempo resources |
| `TempoStorageHigh` | Warning | Expand PVC or reduce retention |

PrometheusRule alerts defined in `kubernetes/monitoring/tempo-alerts.yaml`.
