# Staging Deployment Validation Runbook

**Task:** B-05 — Validate Staging Deployment
**Design Reference:** Section 13.2 (Phase B description)
**Purpose:** Manual validation of containerised FABRIC application before GitOps (Phase C) takes over

---

## Prerequisites

- AKS cluster provisioned (B-01)
- PostgreSQL deployed and accessible (B-02)
- NGINX Ingress Controller deployed (B-03)
- DNS records configured (B-04)
- Container image built and pushed to ghcr.io (A-01)

## 1. Get AKS Credentials

```bash
# Get kubeconfig for the FABRIC cluster
az aks get-credentials \
  --resource-group fabric-rg \
  --name fabric-aks \
  --overwrite-existing

# Verify access
kubectl get nodes
kubectl get namespaces
```

## 2. Deploy FABRIC Application to Staging

```bash
# Verify staging namespace exists
kubectl get namespace staging

# Deploy using the staging Kustomize overlay
kubectl apply -k overlays/staging/

# Wait for deployment to be ready
kubectl rollout status deployment/fabric -n staging --timeout=120s
```

## 3. Health Check Endpoint Validation

```bash
# Port-forward to the application
kubectl port-forward -n staging svc/fabric 8080:80 &

# Test health endpoint
curl -s http://localhost:8080/healthz
# Expected: 200 OK

# Test metrics endpoint
curl -s http://localhost:8080/metrics | head -20
# Expected: Prometheus metrics output

# Clean up port-forward
kill %1
```

## 4. PostgreSQL Connectivity

```bash
# Exec into the FABRIC pod
FABRIC_POD=$(kubectl get pod -n staging -l app.kubernetes.io/name=fabric -o jsonpath='{.items[0].metadata.name}')

# Verify DATABASE_URL is set
kubectl exec -n staging "${FABRIC_POD}" -- printenv DATABASE_URL
# Expected: postgresql://...@fabric-postgresql.postgres.database.azure.com:5432/fabric_staging

# Verify PostgreSQL is reachable from within the pod
kubectl exec -n staging "${FABRIC_POD}" -- \
  sh -c 'node -e "const pg = require(\"pg\"); const c = new pg.Client(process.env.DATABASE_URL); c.connect().then(() => { console.log(\"Connected\"); c.end(); }).catch(e => { console.error(e.message); process.exit(1); })"'
# Expected: "Connected"
```

## 5. External Access via Ingress

```bash
# Get NGINX Ingress external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test via DNS (if DNS is configured)
curl -s https://staging.fabric.internal/healthz
# Expected: 200 OK

# Test via IP (if DNS is not yet propagated)
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s -H "Host: staging.fabric.internal" "http://${INGRESS_IP}/healthz"
```

## 6. Validation Checklist

| Check | Command | Expected Result | Status |
|-------|---------|-----------------|--------|
| Application starts | `kubectl get pods -n staging` | 1/1 Running | [ ] |
| Health check responds | `curl /healthz` | 200 OK | [ ] |
| Metrics endpoint works | `curl /metrics` | Prometheus metrics | [ ] |
| PostgreSQL connected | Pod exec test | "Connected" | [ ] |
| External access works | `curl staging.fabric.internal` | 200 OK | [ ] |
| Logs visible | `kubectl logs -n staging <pod>` | Application logs | [ ] |

## 7. Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Pod CrashLoopBackOff | `kubectl logs -n staging <pod>` | Check env vars, image tag |
| ImagePullBackOff | `kubectl describe pod -n staging <pod>` | Check ghcr.io credentials |
| Health check fails | `kubectl exec <pod> -- curl localhost:3000/healthz` | Check application startup |
| DB connection fails | Check VNet peering, NSG rules | Verify PostgreSQL VNet integration |
| Ingress 502/504 | `kubectl logs -n ingress-nginx <pod>` | Check backend service port mapping |

## 8. Post-Validation

After successful validation:
1. This manual deployment confirms the container image and infrastructure work together
2. Phase C (GitOps) takes over — Argo CD will manage all future deployments
3. Remove any manually-applied resources that Argo CD will now manage
