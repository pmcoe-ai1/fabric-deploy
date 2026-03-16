# Unified Upgrade Process

**Scope:** All self-hosted FABRIC platform components
**Task:** J-05 — Documented upgrade order, pre/post checklists, rollback procedures

---

## 1. Upgrade Order

Components must be upgraded in this order to respect dependencies:

```
1. External Secrets Operator (ESO)      — no dependencies
2. HashiCorp Vault                       — ESO syncs from Vault
3. Prometheus / Grafana (kube-prometheus-stack) — monitoring must be healthy before app changes
4. Loki                                  — depends on Grafana data source
5. Tempo                                 — depends on Grafana data source
6. Argo CD                               — manages deployments
7. Argo Rollouts                         — manages progressive delivery
8. NGINX Ingress Controller              — traffic routing (upgrade last to avoid disruption)
```

**Why this order?**
- ESO first: if ESO breaks, secrets stop syncing — fix it before touching Vault
- Vault before monitoring: if Vault breaks during upgrade, monitoring shows the issue
- Monitoring before CD: if monitoring breaks, analysis templates fail — fix monitoring first
- CD before ingress: if Argo breaks, rollouts stall but traffic continues; ingress break = outage

---

## 2. Scheduled Cadence

| Activity | Frequency | Owner |
|----------|-----------|-------|
| Dependency review (check for new Helm chart versions) | Monthly | Platform team |
| Minor version upgrades (patch, security fixes) | Monthly | Platform team |
| Major version upgrades (breaking changes) | Quarterly | Platform team + review |
| Kubernetes version upgrade | Bi-annually | Platform team + review |

---

## 3. Pre-Upgrade Checklist (All Components)

Before upgrading any component:

- [ ] Read the changelog / release notes for the target version
- [ ] Check for breaking changes or required migration steps
- [ ] Verify current component health:
  ```bash
  kubectl get pods -n <namespace>
  # All pods should be Running/Ready
  ```
- [ ] Take backups:
  - Vault: Raft snapshot (`vault operator raft snapshot save`)
  - Grafana: DB backup (see `runbooks/prometheus-grafana.md`)
  - PostgreSQL: Azure automatic backup is continuous
- [ ] Notify team in #fabric-ops Slack channel
- [ ] Create GitHub Issue from template (see Section 7)

---

## 4. Per-Component Upgrade Procedures

### 4.1 External Secrets Operator

```bash
# Pre-check
kubectl get pods -n external-secrets
kubectl get externalsecrets -A  # All should show "SecretSynced"

# Upgrade
# Update version in terraform/external-secrets.tf
terraform plan -target=helm_release.external_secrets
terraform apply -target=helm_release.external_secrets

# Post-check
kubectl get pods -n external-secrets
kubectl get externalsecrets -A  # Verify all still "SecretSynced"
```

**Rollback:** `terraform apply -target=helm_release.external_secrets` with previous version

### 4.2 HashiCorp Vault

See `runbooks/vault.md` Section 6 for detailed procedure.

```bash
# Pre-check
kubectl exec -n vault vault-0 -- vault status  # Must be unsealed
vault operator raft snapshot save /tmp/pre-upgrade.snap

# Upgrade
terraform plan -target=helm_release.vault
terraform apply -target=helm_release.vault

# Post-check (rolling restart — pods restart one at a time)
kubectl get pods -n vault -w
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-0 -- vault version
```

**Rollback:** Restore Raft snapshot + downgrade Helm chart version

### 4.3 Prometheus / Grafana (kube-prometheus-stack)

See `runbooks/prometheus-grafana.md` Section 4 for detailed procedure.

```bash
# Pre-check
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Check http://localhost:9090/targets — all targets up

# Check for CRD changes (major versions)
# https://github.com/prometheus-community/helm-charts/releases

# Upgrade
terraform plan -target=helm_release.kube_prometheus_stack
terraform apply -target=helm_release.kube_prometheus_stack

# Post-check
kubectl get pods -n monitoring
# Verify all targets still up, dashboards accessible
```

**Rollback:** Downgrade Helm chart version; CRD rollback may require manual kubectl apply

### 4.4 Loki

See `runbooks/loki.md` Section 4 for detailed procedure.

```bash
# Pre-check
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Upgrade
terraform plan -target=helm_release.loki
terraform apply -target=helm_release.loki

# Post-check
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
# Verify LogQL queries work in Grafana
```

**Rollback:** Downgrade Helm chart version

### 4.5 Tempo

See `runbooks/tempo.md` Section 4 for detailed procedure.

```bash
# Pre-check
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo

# Upgrade
terraform plan -target=helm_release.tempo
terraform apply -target=helm_release.tempo

# Post-check
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
# Verify traces visible in Grafana
```

**Rollback:** Downgrade Helm chart version

### 4.6 Argo CD

```bash
# Pre-check
kubectl get pods -n argocd
kubectl get applications -n argocd  # All should be Healthy/Synced

# Upgrade
terraform plan -target=helm_release.argocd
terraform apply -target=helm_release.argocd

# Post-check
kubectl get pods -n argocd
kubectl get applications -n argocd  # Verify all apps re-sync
argocd version --server argocd.fabric.internal
```

**Rollback:** Downgrade Helm chart; applications will re-sync automatically

### 4.7 Argo Rollouts

```bash
# Pre-check
kubectl get pods -n argo-rollouts
kubectl get rollouts -n staging
kubectl get rollouts -n production

# Upgrade
terraform plan -target=helm_release.argo_rollouts
terraform apply -target=helm_release.argo_rollouts

# Post-check
kubectl get pods -n argo-rollouts
kubectl get rollouts -A  # Verify rollout statuses unchanged
```

**Rollback:** Downgrade Helm chart version

### 4.8 NGINX Ingress Controller

```bash
# Pre-check — this is the most sensitive upgrade (traffic disruption risk)
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx  # Note external IP

# Upgrade (rolling update — zero downtime if 2+ replicas)
terraform plan -target=helm_release.nginx_ingress
terraform apply -target=helm_release.nginx_ingress

# Post-check
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx  # External IP should be unchanged
curl https://staging.fabric.internal/healthz
curl https://fabric.internal/healthz
```

**Rollback:** Downgrade Helm chart version; external IP is preserved

---

## 5. Post-Upgrade Verification Checklist

After upgrading any component:

- [ ] All pods in the component namespace are Running/Ready
- [ ] No new alerts firing in Alertmanager
- [ ] Grafana dashboards show live data
- [ ] Application health checks pass:
  ```bash
  curl https://staging.fabric.internal/healthz
  curl https://fabric.internal/healthz
  ```
- [ ] Argo CD shows all applications Healthy/Synced
- [ ] ExternalSecrets show "SecretSynced" status
- [ ] Update the GitHub Issue with results
- [ ] Notify team in #fabric-ops that upgrade is complete

---

## 6. Emergency Rollback Procedure

If an upgrade causes an outage:

```bash
# 1. Identify the failed component
kubectl get pods -A | grep -v Running

# 2. Rollback the Helm chart to previous version
# Edit terraform/<component>.tf — revert version number
terraform apply -target=helm_release.<component>

# 3. If Terraform state is corrupted
helm rollback <release-name> <previous-revision> -n <namespace>
# Example: helm rollback vault 3 -n vault

# 4. Verify recovery
kubectl get pods -n <namespace>
# Run post-upgrade checklist (Section 5)
```

---

## 7. GitHub Issue Template for Upgrade Tracking

Create a new GitHub Issue with this template for each upgrade:

```markdown
## Component Upgrade: [Component Name] v[old] → v[new]

### Pre-Upgrade
- [ ] Read changelog: [link]
- [ ] Breaking changes: None / [list]
- [ ] Backups taken
- [ ] Team notified

### Upgrade
- [ ] Terraform plan reviewed
- [ ] Terraform apply successful
- [ ] Pods healthy

### Post-Upgrade
- [ ] No new alerts
- [ ] Dashboards showing data
- [ ] Health checks passing
- [ ] Team notified of completion

### Rollback (if needed)
- [ ] Rolled back to v[old]
- [ ] Root cause documented
```

---

## 8. Version Matrix (Current)

| Component | Helm Chart | Chart Version | App Version |
|-----------|-----------|---------------|-------------|
| ESO | external-secrets | 0.9.13 | 0.9.13 |
| Vault | hashicorp/vault | 0.28.0 | 1.15.x |
| kube-prometheus-stack | prometheus-community | 58.2.2 | 0.73.x |
| Loki | grafana/loki | 6.6.2 | 3.x |
| Promtail | grafana/promtail | 6.16.4 | 3.x |
| Tempo | grafana/tempo | 1.10.1 | 2.x |
| OTel Collector | opentelemetry | 0.92.0 | 0.98.x |
| Argo CD | argoproj/argo-cd | 6.7.3 | 2.10.x |
| Argo Rollouts | argoproj/argo-rollouts | 2.35.1 | 1.6.x |
| NGINX Ingress | ingress-nginx | 4.10.0 | 1.10.x |

Update this table after each upgrade.
