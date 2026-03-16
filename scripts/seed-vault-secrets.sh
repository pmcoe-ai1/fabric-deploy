#!/usr/bin/env bash
# E-02 — Store Secrets in Vault
# Design Reference: Section 8.1 (Secrets Inventory)
#
# This script seeds HashiCorp Vault with the required FABRIC secrets.
# Run this once after Vault is deployed and unsealed (E-01 complete).
#
# Prerequisites:
#   - Vault CLI installed and in PATH
#   - VAULT_ADDR set (e.g., https://vault.fabric.internal or kubectl port-forward)
#   - VAULT_TOKEN set (root token or token with write access)
#   - PostgreSQL connection strings available
#   - ANTHROPIC_API_KEY available
#
# Usage:
#   export VAULT_ADDR=https://vault.fabric.internal
#   export VAULT_TOKEN=<root-token>
#   ./scripts/seed-vault-secrets.sh
#
# Secrets that remain in GitHub Actions (NOT migrated to Vault per Section 8.1):
#   - GITHUB_TOKEN — auto-rotated by GitHub
#   - Container registry credentials — auto-rotated by GitHub (ghcr.io)
#   - Vault unseal keys — stored in Azure Key Vault, not HashiCorp Vault

set -euo pipefail

# --- Validation ---
if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "ERROR: VAULT_ADDR is not set. Set it to the Vault address (e.g., https://vault.fabric.internal)"
  exit 1
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "ERROR: VAULT_TOKEN is not set. Set it to a Vault token with write access."
  exit 1
fi

echo "=== FABRIC Vault Secret Seeding ==="
echo "Vault address: ${VAULT_ADDR}"
echo ""

# --- Enable KV v2 secrets engine if not already enabled ---
echo "[1/6] Enabling KV v2 secrets engine at secret/..."
vault secrets enable -path=secret -version=2 kv 2>/dev/null || echo "  (already enabled)"

# --- Enable Kubernetes auth method ---
echo "[2/6] Enabling Kubernetes auth method..."
vault auth enable kubernetes 2>/dev/null || echo "  (already enabled)"

# Configure Kubernetes auth (uses in-cluster service account)
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" 2>/dev/null || echo "  (already configured)"

# --- Staging Database Secret ---
echo "[3/6] Writing staging database secret..."
if [[ -z "${STAGING_DATABASE_URL:-}" ]]; then
  echo "  WARNING: STAGING_DATABASE_URL not set. Using placeholder."
  STAGING_DATABASE_URL="postgresql://fabricadmin:CHANGE_ME@fabric-postgresql.postgres.database.azure.com:5432/fabric_staging?sslmode=require"
fi
vault kv put secret/fabric/staging/database \
  DATABASE_URL="${STAGING_DATABASE_URL}"
echo "  Written: secret/fabric/staging/database"

# --- Production Database Secret ---
echo "[4/6] Writing production database secret..."
if [[ -z "${PRODUCTION_DATABASE_URL:-}" ]]; then
  echo "  WARNING: PRODUCTION_DATABASE_URL not set. Using placeholder."
  PRODUCTION_DATABASE_URL="postgresql://fabricadmin:CHANGE_ME@fabric-postgresql.postgres.database.azure.com:5432/fabric_production?sslmode=require"
fi
vault kv put secret/fabric/production/database \
  DATABASE_URL="${PRODUCTION_DATABASE_URL}"
echo "  Written: secret/fabric/production/database"

# --- Shared Anthropic API Key ---
echo "[5/6] Writing shared Anthropic API key..."
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "  WARNING: ANTHROPIC_API_KEY not set. Using placeholder."
  ANTHROPIC_API_KEY="sk-ant-CHANGE_ME"
fi
vault kv put secret/fabric/shared/anthropic \
  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
echo "  Written: secret/fabric/shared/anthropic"

# --- Shared Grafana Admin Password ---
echo "[6/6] Writing shared Grafana admin password..."
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "  WARNING: GRAFANA_ADMIN_PASSWORD not set. Using placeholder."
  GRAFANA_ADMIN_PASSWORD="admin"
fi
vault kv put secret/fabric/shared/grafana \
  admin_password="${GRAFANA_ADMIN_PASSWORD}"
echo "  Written: secret/fabric/shared/grafana"

# --- Create Vault policies for FABRIC application ---
echo ""
echo "=== Creating Vault Policies ==="

# Staging policy — read-only access to staging secrets
vault policy write fabric-staging - <<POLICY
path "secret/data/fabric/staging/*" {
  capabilities = ["read"]
}
path "secret/data/fabric/shared/*" {
  capabilities = ["read"]
}
POLICY
echo "  Created policy: fabric-staging"

# Production policy — read-only access to production secrets
vault policy write fabric-production - <<POLICY
path "secret/data/fabric/production/*" {
  capabilities = ["read"]
}
path "secret/data/fabric/shared/*" {
  capabilities = ["read"]
}
POLICY
echo "  Created policy: fabric-production"

# --- Create Kubernetes auth roles ---
echo ""
echo "=== Creating Kubernetes Auth Roles ==="

vault write auth/kubernetes/role/fabric-staging \
  bound_service_account_names=fabric \
  bound_service_account_namespaces=staging \
  policies=fabric-staging \
  ttl=1h
echo "  Created role: fabric-staging"

vault write auth/kubernetes/role/fabric-production \
  bound_service_account_names=fabric \
  bound_service_account_namespaces=production \
  policies=fabric-production \
  ttl=1h
echo "  Created role: fabric-production"

echo ""
echo "=== Vault Secret Seeding Complete ==="
echo ""
echo "Verify with:"
echo "  vault kv get secret/fabric/staging/database"
echo "  vault kv get secret/fabric/production/database"
echo "  vault kv get secret/fabric/shared/anthropic"
echo "  vault kv get secret/fabric/shared/grafana"
echo ""
echo "Secrets remaining in GitHub Actions (per Section 8.1):"
echo "  - GITHUB_TOKEN (auto-rotated)"
echo "  - Container registry credentials (auto-rotated)"
echo "  - Vault unseal keys (in Azure Key Vault)"
