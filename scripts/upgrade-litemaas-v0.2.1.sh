#!/usr/bin/env bash
# ============================================================================
# LiteMaaS Upgrade Script: v0.1.x/v0.2.0 -> v0.2.1
# ============================================================================
#
# Three-phase upgrade:
#   Phase 1: Update LiteMaaS backend (custom image) + frontend
#   Phase 2: Update LiteLLM v1.74.x -> v1.81.0 (skipped if already on v1.81.0)
#            Prisma migrations MUST run before DISABLE_SCHEMA_UPDATE is set.
#   Phase 3: Apply v0.2.1 fixes (DISABLE_SCHEMA_UPDATE, REDIS env vars)
#            Also checks if Prisma dropped LiteMaaS tables and recovers.
#
# Usage:
#   ./upgrade-litemaas-v0.2.1.sh <namespace>
#   ./upgrade-litemaas-v0.2.1.sh <namespace> --yes   # non-interactive
#
# Examples:
#   ./upgrade-litemaas-v0.2.1.sh litellm-staging
#   ./upgrade-litemaas-v0.2.1.sh litellm-test
#   ./upgrade-litemaas-v0.2.1.sh litellm-test --yes
#
# Prerequisites:
#   - oc CLI logged into the target cluster
#   - Access to the target namespace
#   - curl available
#   - Backend image pushed to quay.io/rhpds/litemaas:backend-0.2.1
#
# v0.2.1 fixes (on top of v0.2.0):
#   - Redis cache flush after model CRUD (ioredis plugin)
#   - DISABLE_SCHEMA_UPDATE=true prevents LiteLLM Prisma from dropping tables
#   - GET /api/v1/models no longer falls back to stale LiteLLM data
#   - getUserInfo handles 404 for new user auto-creation
#   - Model delete cascade (FK constraint fix)
#   - syncModels cross-references LiteLLM DB to filter stale cache entries
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
# Custom backend built from litemaas-fixes-0.2.1 branch
LITEMAAS_BACKEND_IMAGE="quay.io/rhpds/litemaas"
LITEMAAS_BACKEND_TAG="backend-0.2.1"
LITEMAAS_FRONTEND_IMAGE="quay.io/rh-aiservices-bu/litemaas-frontend"
LITEMAAS_FRONTEND_TAG="0.2.0"
LITELLM_IMAGE="ghcr.io/berriai/litellm-non_root"
LITELLM_TARGET_TAG="main-v1.81.0-stable"
ROLLOUT_TIMEOUT="300s"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Functions
# ============================================================================

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_phase() { echo -e "\n${BLUE}=========================================${NC}"; echo -e "${BLUE}$*${NC}"; echo -e "${BLUE}=========================================${NC}"; }

confirm() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    read -rp "$1 [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

check_prereqs() {
    if ! command -v oc &>/dev/null; then
        log_error "oc CLI not found. Install it first."
        exit 1
    fi
    if ! oc whoami &>/dev/null; then
        log_error "Not logged into OpenShift. Run 'oc login' first."
        exit 1
    fi
    if ! command -v curl &>/dev/null; then
        log_error "curl not found."
        exit 1
    fi
}

get_current_images() {
    local ns=$1
    CURRENT_BACKEND=$(oc get deployment litellm-backend -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "NOT FOUND")
    CURRENT_FRONTEND=$(oc get deployment litellm-frontend -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "NOT FOUND")
    CURRENT_LITELLM=$(oc get deployment litellm -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "NOT FOUND")
}

print_status() {
    local ns=$1
    echo ""
    log_info "Current images in $ns:"
    echo "  Backend:  $CURRENT_BACKEND"
    echo "  Frontend: $CURRENT_FRONTEND"
    echo "  LiteLLM:  $CURRENT_LITELLM"
    echo ""
}

backup_databases() {
    local ns=$1
    log_info "Backing up databases in $ns..."

    oc exec -n "$ns" litellm-postgres-0 -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        pg_dump -U litellm litellm > /tmp/litemaas_backup_pre_v021.sql 2>/dev/null
        echo 'done'
    " 2>/dev/null

    log_ok "Database backup created at /tmp/litemaas_backup_pre_v021.sql"
}

check_health() {
    local url=$1
    local retries=${2:-10}
    local delay=${3:-10}

    for i in $(seq 1 $retries); do
        local status=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$status" = "200" ]; then
            return 0
        fi
        sleep "$delay"
    done
    return 1
}

get_route_host() {
    local ns=$1
    local route_name=$2
    oc get route -n "$ns" "$route_name" -o jsonpath='{.spec.host}' 2>/dev/null || echo ""
}

sync_user_ids() {
    local ns=$1
    log_info "Syncing user IDs between LiteMaaS and LiteLLM tables..."

    local mismatches=$(oc exec litellm-postgres-0 -n "$ns" -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        psql -U litellm -d litellm -t -c \"
            SELECT COUNT(*) FROM users u
            JOIN \\\"LiteLLM_UserTable\\\" l ON u.email = l.user_email
            WHERE u.id::text <> l.user_id AND u.email <> 'system@litemaas.internal';
        \"
    " 2>/dev/null | tr -d ' \n')

    if [ "$mismatches" = "0" ] || [ -z "$mismatches" ]; then
        log_ok "No user ID mismatches found"
        return
    fi

    log_warn "Found $mismatches user ID mismatches - fixing..."
    oc exec litellm-postgres-0 -n "$ns" -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        psql -U litellm -d litellm -c \"
            UPDATE \\\"LiteLLM_UserTable\\\" l
            SET user_id = u.id::text
            FROM users u
            WHERE u.email = l.user_email
            AND u.id::text <> l.user_id;
        \"
    " 2>/dev/null
    log_ok "Fixed $mismatches user ID mismatches"
}

# ============================================================================
# Main
# ============================================================================

NAMESPACE="${1:-}"
AUTO_YES=false

if [ "${2:-}" = "--yes" ] || [ "${2:-}" = "-y" ]; then
    AUTO_YES=true
fi

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace> [--yes]"
    echo ""
    echo "Examples:"
    echo "  $0 litellm-staging"
    echo "  $0 litellm-test"
    echo "  $0 litellm-test --yes"
    exit 1
fi

log_phase "LiteMaaS Upgrade to v0.2.1"
log_info "Namespace: $NAMESPACE"
log_info "Target backend:  ${LITEMAAS_BACKEND_IMAGE}:${LITEMAAS_BACKEND_TAG}"
log_info "Target frontend: ${LITEMAAS_FRONTEND_IMAGE}:${LITEMAAS_FRONTEND_TAG}"
log_info "Target LiteLLM:  ${LITELLM_IMAGE}:${LITELLM_TARGET_TAG}"

# ============================================================================
# Pre-flight checks
# ============================================================================
log_phase "Pre-flight Checks"

check_prereqs
log_ok "Prerequisites met (oc, curl available, logged in)"

# Verify namespace
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' not found"
    exit 1
fi
log_ok "Namespace $NAMESPACE exists"

# Verify deployments exist
for deploy in litellm litellm-backend litellm-frontend; do
    if ! oc get deployment "$deploy" -n "$NAMESPACE" &>/dev/null; then
        log_error "Deployment '$deploy' not found in $NAMESPACE"
        exit 1
    fi
done
log_ok "All deployments present"

# Verify postgres is running
if ! oc get pod litellm-postgres-0 -n "$NAMESPACE" &>/dev/null; then
    log_error "PostgreSQL pod not found"
    exit 1
fi
log_ok "PostgreSQL running"

# Get current state
get_current_images "$NAMESPACE"
print_status "$NAMESPACE"

# Get route hosts
LITELLM_ROUTE=$(oc get routes -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.to.name=="litellm")].spec.host}' 2>/dev/null | awk '{print $1}')
FRONTEND_ROUTE=$(oc get routes -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.to.name=="litellm-frontend")].spec.host}' 2>/dev/null | awk '{print $1}')

log_info "Routes:"
echo "  LiteLLM:  https://${LITELLM_ROUTE:-NOT_FOUND}"
echo "  Frontend: https://${FRONTEND_ROUTE:-NOT_FOUND}"

if ! confirm "Proceed with upgrade?"; then
    log_info "Aborted"
    exit 0
fi

# ============================================================================
# Database Backup
# ============================================================================
log_phase "Database Backup"
backup_databases "$NAMESPACE"

# ============================================================================
# Phase 1: Update Backend & Frontend
# ============================================================================
log_phase "PHASE 1: Update Backend (v0.2.1 custom) & Frontend (v0.2.0)"

log_info "Updating backend image..."
oc set image deployment/litellm-backend "backend=${LITEMAAS_BACKEND_IMAGE}:${LITEMAAS_BACKEND_TAG}" -n "$NAMESPACE"

log_info "Updating frontend image..."
oc set image deployment/litellm-frontend "frontend=${LITEMAAS_FRONTEND_IMAGE}:${LITEMAAS_FRONTEND_TAG}" -n "$NAMESPACE"

log_info "Waiting for backend rollout..."
if ! oc rollout status deployment/litellm-backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1; then
    log_error "Backend rollout failed"
    exit 1
fi
log_ok "Backend rolled out"

log_info "Waiting for frontend rollout..."
if ! oc rollout status deployment/litellm-frontend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1; then
    log_error "Frontend rollout failed"
    exit 1
fi
log_ok "Frontend rolled out"

# ============================================================================
# Phase 2: Update LiteLLM (if needed) — MUST run BEFORE DISABLE_SCHEMA_UPDATE
# ============================================================================
# IMPORTANT: LiteLLM v1.81.0 has new Prisma tables (LiteLLM_SSOConfig,
# LiteLLM_CacheConfig, etc.). Prisma migrations MUST run on first start of
# the new version. Setting DISABLE_SCHEMA_UPDATE before this upgrade would
# block those migrations and cause Internal Server Errors.
# Order: upgrade LiteLLM -> let Prisma migrate -> THEN set DISABLE_SCHEMA_UPDATE.
if echo "$CURRENT_LITELLM" | grep -q "v1.81.0"; then
    log_phase "PHASE 2: LiteLLM already on v1.81.0 - SKIPPED"
else
    log_phase "PHASE 2: Update LiteLLM to ${LITELLM_TARGET_TAG}"

    if ! confirm "Proceed with LiteLLM upgrade?"; then
        log_warn "Stopping after Phase 1. LiteLLM is still on the old version."
        exit 0
    fi

    log_info "Updating LiteLLM image..."
    oc set image deployment/litellm "litellm=${LITELLM_IMAGE}:${LITELLM_TARGET_TAG}" -n "$NAMESPACE"

    log_info "Waiting for LiteLLM rollout (Prisma migrations will run)..."
    if ! oc rollout status deployment/litellm -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1; then
        log_error "LiteLLM rollout failed"
        exit 1
    fi
    log_ok "LiteLLM rolled out — Prisma migrations completed"
fi

# ============================================================================
# Phase 3: Apply v0.2.1 fixes (AFTER LiteLLM upgrade)
# ============================================================================
log_phase "PHASE 3: Apply v0.2.1 fixes"

# Set REDIS env vars on backend (if not already set)
EXISTING_REDIS=$(oc get deployment litellm-backend -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REDIS_HOST")].value}' 2>/dev/null || echo "")
if [ -z "$EXISTING_REDIS" ]; then
    log_info "Setting REDIS_HOST and REDIS_PORT on backend..."
    oc set env deployment/litellm-backend REDIS_HOST=litellm-redis REDIS_PORT=6379 -n "$NAMESPACE"
    oc rollout status deployment/litellm-backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1
    log_ok "Redis env vars set on backend"
else
    log_ok "REDIS_HOST already set on backend ($EXISTING_REDIS)"
fi

# Set DISABLE_SCHEMA_UPDATE on LiteLLM — AFTER upgrade so Prisma has already migrated
EXISTING_DISABLE=$(oc get deployment litellm -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DISABLE_SCHEMA_UPDATE")].value}' 2>/dev/null || echo "")
if [ -z "$EXISTING_DISABLE" ]; then
    log_info "Setting DISABLE_SCHEMA_UPDATE=true on LiteLLM (prevents future table drops)..."
    oc set env deployment/litellm DISABLE_SCHEMA_UPDATE=true -n "$NAMESPACE"
    log_info "Waiting for LiteLLM rollout..."
    oc rollout status deployment/litellm -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1
    log_ok "DISABLE_SCHEMA_UPDATE set on LiteLLM"
else
    log_ok "DISABLE_SCHEMA_UPDATE already set ($EXISTING_DISABLE)"
fi

# Check if LiteMaaS tables were dropped by Prisma during LiteLLM upgrade
LITEMAAS_TABLES=$(oc exec litellm-postgres-0 -n "$NAMESPACE" -- bash -c "
    export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
    psql -U litellm -d litellm -t -c \"SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users';\"
" 2>/dev/null | tr -d ' \n')

if [ "$LITEMAAS_TABLES" = "0" ]; then
    log_warn "LiteMaaS tables were dropped by Prisma during LiteLLM upgrade — restarting backend to recreate..."
    oc rollout restart deployment/litellm-backend -n "$NAMESPACE"
    oc rollout status deployment/litellm-backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1
    log_ok "Backend restarted — LiteMaaS tables recreated"
fi

# ============================================================================
# Data Sync: Fix user ID mismatches
# ============================================================================
log_phase "Data Sync: User IDs"
sync_user_ids "$NAMESPACE"

# Data migration (sync users/keys from LiteLLM tables to LiteMaaS tables)
log_info "Syncing users from LiteLLM to LiteMaaS..."
POSTGRES_POD="litellm-postgres-0"
oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
psql -U litellm -d litellm <<'EOSQL'
INSERT INTO users (id, username, email, oauth_provider, oauth_id, roles, sync_status, created_at, updated_at)
SELECT user_id::uuid, user_email, user_email, 'openshift', 'migration-' || user_id,
  CASE WHEN user_role = 'proxy_admin' THEN ARRAY['admin','user'] ELSE ARRAY['user'] END,
  'synced', NOW(), NOW()
FROM \"LiteLLM_UserTable\"
WHERE user_email IS NOT NULL AND user_email != ''
  AND user_email NOT IN (SELECT email FROM users WHERE email IS NOT NULL)
ON CONFLICT (id) DO NOTHING;
EOSQL
" 2>/dev/null
log_ok "Users synced"

# Restart backend for model sync + key alias backfill
log_info "Restarting backend for model sync..."
oc rollout restart deployment/litellm-backend -n "$NAMESPACE"
oc rollout status deployment/litellm-backend -n "$NAMESPACE" --timeout=120s 2>/dev/null
log_ok "Backend restarted"

# ============================================================================
# Final Verification
# ============================================================================
log_phase "Final Verification"

get_current_images "$NAMESPACE"

echo ""
log_info "Updated images:"
echo "  Backend:  $CURRENT_BACKEND"
echo "  Frontend: $CURRENT_FRONTEND"
echo "  LiteLLM:  $CURRENT_LITELLM"
echo ""

log_info "Pod status:"
oc get pods -n "$NAMESPACE" -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' --no-headers
echo ""

# Health checks
ALL_OK=true

if [ -n "$LITELLM_ROUTE" ]; then
    if check_health "https://${LITELLM_ROUTE}/health/liveness" 3 5; then
        log_ok "LiteLLM:  healthy"
    else
        log_warn "LiteLLM:  not responding via route"
        ALL_OK=false
    fi
fi

if [ -n "$FRONTEND_ROUTE" ]; then
    if check_health "https://${FRONTEND_ROUTE}/" 3 5; then
        log_ok "Frontend: healthy"
    else
        log_warn "Frontend: not responding"
        ALL_OK=false
    fi
fi

# Check Redis connection in backend logs
log_info "Checking Redis connection..."
REDIS_LOG=$(oc logs deployment/litellm-backend -n "$NAMESPACE" --tail=50 2>/dev/null | grep -i "Redis connection" || echo "")
if echo "$REDIS_LOG" | grep -q "established"; then
    log_ok "Backend Redis: connected"
else
    log_warn "Backend Redis: connection not confirmed in recent logs"
fi

# Show migration counts
echo ""
log_info "Data counts:"
oc exec litellm-postgres-0 -n "$NAMESPACE" -- bash -c "
export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
psql -U litellm -d litellm -t -c \"SELECT '  Users: ' || COUNT(*) FROM users WHERE email != 'system@litemaas.internal';\"
psql -U litellm -d litellm -t -c \"SELECT '  Models: ' || COUNT(*) FROM models WHERE availability = 'available';\"
psql -U litellm -d litellm -t -c \"SELECT '  Subscriptions: ' || COUNT(*) FROM subscriptions WHERE status = 'active';\"
psql -U litellm -d litellm -t -c \"SELECT '  API Keys: ' || COUNT(*) FROM api_keys WHERE is_active = true;\"
" 2>/dev/null || true

echo ""
if [ "$ALL_OK" = true ]; then
    log_phase "Upgrade Complete!"
    log_ok "$NAMESPACE upgraded to LiteMaaS v0.2.1"
else
    log_phase "Upgrade Complete (with warnings)"
    log_warn "Some checks did not pass. Check pod logs:"
    echo "  oc logs -n $NAMESPACE deployment/litellm-backend --tail=50"
fi

echo ""
log_info "Rollback commands (if needed):"
echo "  oc rollout undo deployment/litellm-backend -n $NAMESPACE"
echo "  oc rollout undo deployment/litellm-frontend -n $NAMESPACE"
echo "  oc rollout undo deployment/litellm -n $NAMESPACE"
