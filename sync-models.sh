#!/bin/bash
# =============================================================================
# LiteMaaS Model Sync Script
# =============================================================================
# Syncs models from LiteLLM to backend database
#
# Usage:
#   Automatic mode (auto-discovers all resources):
#     ./sync-models.sh [namespace]
#
#     The script will automatically find:
#     - LiteLLM API route (targeting 'litellm' service)
#     - Secret with LITELLM_MASTER_KEY
#     - Database secret (with username/password/database keys)
#     - PostgreSQL pod (app=litellm-postgres or app=litemaas-postgres)
#
#   Manual mode (bypass auto-discovery):
#     LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh [namespace]
#
#   Examples:
#     # Standard namespace
#     ./sync-models.sh litemaas
#
#     # Custom namespace
#     ./sync-models.sh litellm-rhpds
#
#     # Manual mode
#     LITELLM_URL=https://litellm-prod.apps.cluster.com \
#     LITELLM_MASTER_KEY=sk-Ki6upzR5aSwKDzSHoIWneNvKqx2CcxKj \
#     ./sync-models.sh my-custom-namespace
# =============================================================================

set -e

NAMESPACE="${1:-litemaas}"

echo "========================================="
echo "LiteMaaS Model Sync"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Check if values are provided via environment variables
if [ -n "$LITELLM_URL" ] && [ -n "$LITELLM_MASTER_KEY" ]; then
    echo "Using provided environment variables"
    echo "  LiteLLM URL: $LITELLM_URL"
    echo "  Master Key: ${LITELLM_MASTER_KEY:0:10}..."
else
    echo "Automatic mode: Getting values from OpenShift..."
    echo ""

    # Check if oc is available
    if ! command -v oc &> /dev/null; then
        echo "ERROR: oc command not found. Please install OpenShift CLI."
        echo ""
        echo "Alternatively, provide values manually:"
        echo "  LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh"
        exit 1
    fi

    # Check if jq is available (needed for auto-discovery)
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq command not found. Please install jq."
        echo "  macOS: brew install jq"
        echo "  RHEL/Fedora: dnf install jq"
        echo "  Ubuntu/Debian: apt install jq"
        echo ""
        echo "Alternatively, provide values manually:"
        echo "  LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh"
        exit 1
    fi

    # Check if logged in
    if ! oc whoami &> /dev/null; then
        echo "ERROR: Not logged into OpenShift. Run 'oc login' first."
        echo ""
        echo "Alternatively, provide values manually:"
        echo "  LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh"
        exit 1
    fi

    # Get LiteLLM URL - find route targeting litellm service
    echo "Getting LiteLLM URL..."
    echo "  Discovering routes in namespace '$NAMESPACE'..."

    # Find route that targets the litellm service (API route)
    LITELLM_ROUTE=$(oc get routes -n "$NAMESPACE" -o json 2>/dev/null | \
                    jq -r '.items[] | select(.spec.to.name == "litellm") | .spec.host' 2>/dev/null | head -1)

    # If not found, try finding any route with "litellm" in the service name (but not backend/frontend)
    if [ -z "$LITELLM_ROUTE" ]; then
        LITELLM_ROUTE=$(oc get routes -n "$NAMESPACE" -o json 2>/dev/null | \
                        jq -r '.items[] | select(.spec.to.name | test("litellm|litemaas")) | select(.spec.to.name | test("backend|frontend") | not) | .spec.host' 2>/dev/null | head -1)
    fi

    if [ -z "$LITELLM_ROUTE" ]; then
        echo "ERROR: LiteLLM API route not found in namespace '$NAMESPACE'"
        echo "       Could not find route targeting 'litellm' service"
        echo ""
        echo "Available routes:"
        oc get routes -n "$NAMESPACE" 2>/dev/null || echo "  None found"
        exit 1
    fi
    LITELLM_URL="https://$LITELLM_ROUTE"
    echo "  LiteLLM URL: $LITELLM_URL"

    # Get LiteLLM Master Key - find secret containing LITELLM_MASTER_KEY
    echo "Getting LiteLLM Master Key..."
    echo "  Discovering secrets in namespace '$NAMESPACE'..."

    # Find secret with LITELLM_MASTER_KEY key
    LITELLM_SECRET_NAME=$(oc get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
                          jq -r '.items[] | select(.data.LITELLM_MASTER_KEY != null) | .metadata.name' 2>/dev/null | head -1)

    if [ -z "$LITELLM_SECRET_NAME" ]; then
        echo "ERROR: Secret with LITELLM_MASTER_KEY not found in namespace '$NAMESPACE'"
        exit 1
    fi

    LITELLM_MASTER_KEY=$(oc get secret "$LITELLM_SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
    echo "  Found secret: $LITELLM_SECRET_NAME"
    echo "  Master Key: ${LITELLM_MASTER_KEY:0:10}..."
fi

# Create temporary config file
TEMP_FILE=$(mktemp /tmp/litemaas-sync.XXXXXX.yml)
cat > "$TEMP_FILE" <<EOF
litellm_url: "$LITELLM_URL"
litellm_master_key: "$LITELLM_MASTER_KEY"
ocp4_workload_litemaas_models_namespace: "$NAMESPACE"
ocp4_workload_litemaas_models_backend_enabled: true
ocp4_workload_litemaas_models_sync_from_litellm: true
ocp4_workload_litemaas_models_cleanup_orphaned: true
ocp4_workload_litemaas_models_list: []
EOF

echo ""
echo "Syncing models from LiteLLM to backend database..."
echo ""

# Run the playbook
if ansible-playbook playbooks/manage_models.yml -e @"$TEMP_FILE"; then
    echo ""
    echo "========================================="
    echo "Sync Complete!"
    echo "========================================="
    echo ""

    # Find database secret (contains username, password, database keys)
    DB_SECRET_NAME=$(oc get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
                     jq -r '.items[] | select(.data.username != null and .data.database != null) | .metadata.name' 2>/dev/null | head -1)

    # Find PostgreSQL pod
    POSTGRES_POD=$(oc get pods -n "$NAMESPACE" -l app=litellm-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POSTGRES_POD" ]; then
        POSTGRES_POD=$(oc get pods -n "$NAMESPACE" -l app=litemaas-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [ -n "$DB_SECRET_NAME" ] && [ -n "$POSTGRES_POD" ]; then
        echo "Verify sync:"
        echo "  # Get database credentials from secret"
        echo "  DB_USER=\$(oc get secret $DB_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.username}' | base64 -d)"
        echo "  DB_NAME=\$(oc get secret $DB_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.database}' | base64 -d)"
        echo "  oc exec -n $NAMESPACE $POSTGRES_POD -- \\"
        echo "    psql -U \$DB_USER -d \$DB_NAME -c 'SELECT id, name FROM models;'"
    else
        echo "Verify sync manually:"
        echo "  oc get pods -n $NAMESPACE"
    fi
else
    echo ""
    echo "ERROR: Sync failed. Check the output above for details."
    rm -f "$TEMP_FILE"
    exit 1
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Users can now create subscriptions to models!"
