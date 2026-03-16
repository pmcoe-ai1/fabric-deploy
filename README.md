# fabric-deploy

FABRIC GitOps config repository — Kubernetes manifests, Terraform, Argo CD applications, monitoring configs, and runbooks.

## Purpose

This repository is the **deployment configuration** half of the FABRIC two-repo strategy (Design Doc Section 4.3):

- **FABRIC repo** (`pmcoe-ai1/FABRIC`): Application code, pipeline tools, workflows, scripts
- **This repo** (`pmcoe-ai1/fabric-deploy`): Infrastructure-as-code, Kubernetes manifests, GitOps config

Argo CD watches this repository and syncs changes to the AKS cluster. CI in the FABRIC repo updates image tags here; CD reads from here.

## Structure (target)

```
fabric-deploy/
├── terraform/          — AKS, PostgreSQL, NGINX, DNS, Vault, ESO, Argo CD, Rollouts, monitoring
├── base/               — Kustomize base manifests
├── overlays/
│   ├── staging/        — Staging Kustomize overlay
│   └── production/     — Production Kustomize overlay
└── runbooks/           — Operational runbooks
```

## Environments

| Environment | Namespace | Deployment Strategy |
|-------------|-----------|-------------------|
| Staging     | `staging` | Blue-green (Argo Rollouts) |
| Production  | `production` | 4-step canary (5% → 25% → 50% → 100%) |

## Branch Protection

- `main` branch requires pull request reviews for production overlay changes
- Direct pushes allowed for staging overlay and Terraform changes during initial setup
