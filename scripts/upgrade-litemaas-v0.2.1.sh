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
    log_info "Backing up full database in $ns..."

    oc exec -n "$ns" litellm-postgres-0 -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        pg_dump -U litellm litellm > /tmp/litemaas_backup_pre_v021.sql 2>/dev/null
        echo 'done'
    " 2>/dev/null

    log_ok "Full database backup created at /tmp/litemaas_backup_pre_v021.sql"
}

backup_litemaas_tables() {
    local ns=$1
    log_info "Backing up individual LiteMaaS tables (for selective restore if Prisma drops them)..."

    # Dump each LiteMaaS table individually so we can restore them
    # without touching LiteLLM's Prisma-managed tables
    local tables="users teams team_members models subscriptions api_keys api_key_models subscription_status_history audit_logs daily_usage_cache"
    oc exec -n "$ns" litellm-postgres-0 -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        for table in $tables; do
            if psql -U litellm -d litellm -c \"SELECT 1 FROM \$table LIMIT 1\" &>/dev/null; then
                pg_dump -U litellm -d litellm --data-only --table=\$table --no-owner --no-acl > /tmp/litemaas_backup_\${table}.sql 2>/dev/null
                rows=\$(psql -U litellm -d litellm -t -c \"SELECT COUNT(*) FROM \$table;\" 2>/dev/null | tr -d ' ')
                echo \"  \$table: \$rows rows backed up\"
            else
                echo \"  \$table: not found (skipped)\"
            fi
        done
    " 2>/dev/null

    log_ok "Individual LiteMaaS table backups created in /tmp/litemaas_backup_*.sql"
}

restore_litemaas_tables() {
    local ns=$1
    log_info "Restoring LiteMaaS table data from backups..."

    # Restore in FK dependency order:
    # 1. users, teams (no FK deps)
    # 2. team_members (FK: user_id, team_id)
    # 3. models (no FK deps)
    # 4. subscriptions (FK: user_id, model_id)
    # 5. api_keys (FK: user_id)
    # 6. api_key_models (FK: api_key_id)
    # 7. subscription_status_history (FK: subscription_id)
    # 8. daily_usage_cache, audit_logs
    local ordered_tables="users teams team_members models subscriptions api_keys api_key_models subscription_status_history daily_usage_cache audit_logs"

    oc exec -n "$ns" litellm-postgres-0 -- bash -c "
        export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
        for table in $ordered_tables; do
            if [ -f /tmp/litemaas_backup_\${table}.sql ]; then
                # Disable FK checks during restore, skip conflicts
                psql -U litellm -d litellm -c \"SET session_replication_role = replica;\" 2>/dev/null
                psql -U litellm -d litellm < /tmp/litemaas_backup_\${table}.sql 2>/dev/null
                psql -U litellm -d litellm -c \"SET session_replication_role = DEFAULT;\" 2>/dev/null
                rows=\$(psql -U litellm -d litellm -t -c \"SELECT COUNT(*) FROM \$table;\" 2>/dev/null | tr -d ' ')
                echo \"  \$table: \$rows rows restored\"
            else
                echo \"  \$table: no backup found (skipped)\"
            fi
        done
    " 2>/dev/null

    log_ok "LiteMaaS table data restored"
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
backup_litemaas_tables "$NAMESPACE"

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

# Deploy Redis if not already present
if ! oc get deployment litellm-redis -n "$NAMESPACE" &>/dev/null; then
    log_info "Deploying Redis..."
    oc apply -n "$NAMESPACE" -f - <<'REDIS_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm-redis
  labels:
    app: litellm-redis
    component: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: litellm-redis
  template:
    metadata:
      labels:
        app: litellm-redis
        component: cache
    spec:
      containers:
        - name: redis
          image: quay.io/sclorg/redis-7-c9s:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
              name: redis
          resources:
            requests:
              memory: 128Mi
              cpu: 100m
            limits:
              memory: 256Mi
              cpu: 250m
          livenessProbe:
            tcpSocket:
              port: 6379
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            exec:
              command: ["/bin/sh", "-c", "redis-cli ping | grep PONG"]
            initialDelaySeconds: 10
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: litellm-redis
  labels:
    app: litellm-redis
    component: cache
spec:
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  selector:
    app: litellm-redis
REDIS_EOF
    oc rollout status deployment/litellm-redis -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1
    log_ok "Redis deployed"
else
    log_ok "Redis already deployed"
fi

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

# ============================================================================
# Table Recovery: Check if Prisma dropped LiteMaaS tables and restore
# ============================================================================
log_phase "Table Recovery"

LITEMAAS_TABLES=$(oc exec litellm-postgres-0 -n "$NAMESPACE" -- bash -c "
    export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
    psql -U litellm -d litellm -t -c \"SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users';\"
" 2>/dev/null | tr -d ' \n')

if [ "$LITEMAAS_TABLES" = "0" ]; then
    log_warn "LiteMaaS tables were dropped by Prisma during LiteLLM upgrade"
    log_info "Restarting backend to recreate table schema..."
    oc rollout restart deployment/litellm-backend -n "$NAMESPACE"
    oc rollout status deployment/litellm-backend -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}" 2>&1
    log_ok "Backend restarted — LiteMaaS table schema recreated (empty)"

    log_info "Restoring data from pre-upgrade backups..."
    restore_litemaas_tables "$NAMESPACE"
else
    log_ok "LiteMaaS tables intact — no restore needed"
fi

# ============================================================================
# Data Sync: Users and API Keys
# ============================================================================
log_phase "Data Sync: Users & API Keys"
sync_user_ids "$NAMESPACE"

# Sync users from LiteLLM_UserTable that don't exist in LiteMaaS users table
# Uses real OpenShift UIDs as oauth_id so OAuth login works immediately
log_info "Syncing users from LiteLLM to LiteMaaS..."
POSTGRES_POD="litellm-postgres-0"

# Get emails of users that need migrating
MIGRATE_EMAILS=$(oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
    export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
    psql -U litellm -d litellm -t -c \"
        SELECT l.user_email FROM \\\"LiteLLM_UserTable\\\" l
        WHERE l.user_email IS NOT NULL AND l.user_email != ''
        AND l.user_email NOT IN (SELECT email FROM users WHERE email IS NOT NULL);
    \"
" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)

# Fetch OpenShift user UIDs once (used for both new and existing users)
OC_USERS=$(oc get users -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\n"}{end}' 2>/dev/null || true)

if [ -n "$MIGRATE_EMAILS" ]; then
    log_info "Looking up OpenShift UIDs for migrating users..."
    while IFS= read -r email; do
        [ -z "$email" ] && continue
        OC_UID=$(echo "$OC_USERS" | grep "^${email}	" | awk '{print $2}' || true)
        if [ -z "$OC_UID" ]; then
            log_warn "  No OpenShift user found for $email — using placeholder (will be fixed on first login)"
            OC_UID="migration-placeholder"
        fi

        oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
            export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
            psql -U litellm -d litellm -c \"
                INSERT INTO users (id, username, email, oauth_provider, oauth_id, roles, sync_status, created_at, updated_at)
                SELECT user_id::uuid, user_email, user_email, 'openshift', '$OC_UID',
                    CASE WHEN user_role = 'proxy_admin' THEN ARRAY['admin','user'] ELSE ARRAY['user'] END,
                    'synced', NOW(), NOW()
                FROM \\\"LiteLLM_UserTable\\\"
                WHERE user_email = '$email'
                ON CONFLICT (id) DO UPDATE SET oauth_id = '$OC_UID', updated_at = NOW();
            \"
        " 2>/dev/null
        log_ok "  Migrated $email (oauth_id=${OC_UID:0:8}...)"
    done <<< "$MIGRATE_EMAILS"
else
    log_ok "No new users to migrate"
fi

# Fix any existing users that still have stale 'migration-' oauth_id
log_info "Checking for users with stale oauth_id..."
STALE_EMAILS=$(oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
    export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
    psql -U litellm -d litellm -t -c \"
        SELECT email FROM users WHERE oauth_id LIKE 'migration-%' AND email != 'system@litemaas.internal';
    \"
" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)

if [ -n "$STALE_EMAILS" ]; then
    while IFS= read -r email; do
        [ -z "$email" ] && continue
        OC_UID=$(echo "$OC_USERS" | grep "^${email}	" | awk '{print $2}' || true)
        if [ -n "$OC_UID" ]; then
            oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
                export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
                psql -U litellm -d litellm -c \"
                    UPDATE users SET oauth_id = '$OC_UID', updated_at = NOW() WHERE email = '$email';
                \"
            " 2>/dev/null
            log_ok "  Fixed oauth_id for $email"
        else
            log_warn "  No OpenShift UID found for $email — will be fixed on first login"
        fi
    done <<< "$STALE_EMAILS"
else
    log_ok "No users with stale oauth_id"
fi

# Sync API keys from LiteLLM_VerificationToken to api_keys table
log_info "Syncing API keys from LiteLLM to LiteMaaS..."
oc exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
export PGPASSWORD=\$(printenv POSTGRES_PASSWORD)
psql -U litellm -d litellm <<'EOSQL'
INSERT INTO api_keys (id, user_id, name, key_hash, key_prefix, lite_llm_key_value, permissions, current_spend, is_active, sync_status, litellm_key_alias, created_at, updated_at, last_sync_at)
SELECT
    gen_random_uuid(),
    u.id,
    COALESCE(NULLIF(vt.key_alias, ''), vt.key_name, 'migrated-key'),
    vt.token,
    vt.key_name,
    vt.key_name,
    '{}',
    COALESCE(vt.spend, 0),
    true,
    'synced',
    vt.key_alias,
    COALESCE(vt.created_at, NOW()),
    NOW(),
    NOW()
FROM "LiteLLM_VerificationToken" vt
JOIN users u ON u.id::text = vt.user_id
WHERE vt.token NOT IN (SELECT key_hash FROM api_keys WHERE key_hash IS NOT NULL)
  AND vt.user_id != 'default_user_id';
EOSQL
" 2>/dev/null
log_ok "API keys synced"

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
