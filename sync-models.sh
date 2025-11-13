#!/bin/bash
# =============================================================================
# LiteMaaS Model Sync Script
# =============================================================================
# Syncs models from LiteLLM to backend database
#
# Usage:
#   Automatic mode (gets values from OpenShift):
#     ./sync-models.sh [namespace]
#
#   Manual mode (provide values):
#     LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh [namespace]
#
#   Example:
#     LITELLM_URL=https://litellm-admin.apps.cluster.com \
#     LITELLM_MASTER_KEY=sk-Ki6upzR5aSwKDzSHoIWneNvKqx2CcxKj \
#     ./sync-models.sh litemaas
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

    # Check if logged in
    if ! oc whoami &> /dev/null; then
        echo "ERROR: Not logged into OpenShift. Run 'oc login' first."
        echo ""
        echo "Alternatively, provide values manually:"
        echo "  LITELLM_URL=https://... LITELLM_MASTER_KEY=sk-... ./sync-models.sh"
        exit 1
    fi

    # Get LiteLLM URL
    echo "Getting LiteLLM URL..."
    LITELLM_ROUTE=$(oc get route litemaas -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -z "$LITELLM_ROUTE" ]; then
        echo "ERROR: LiteLLM route not found in namespace '$NAMESPACE'"
        exit 1
    fi
    LITELLM_URL="https://$LITELLM_ROUTE"
    echo "  LiteLLM URL: $LITELLM_URL"

    # Get LiteLLM Master Key
    echo "Getting LiteLLM Master Key..."
    LITELLM_MASTER_KEY=$(oc get secret litellm-secret -n "$NAMESPACE" -o jsonpath='{.data.LITELLM_MASTER_KEY}' 2>/dev/null | base64 -d || echo "")
    if [ -z "$LITELLM_MASTER_KEY" ]; then
        echo "ERROR: LiteLLM master key not found in namespace '$NAMESPACE'"
        exit 1
    fi
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
    echo "Verify sync:"
    echo "  oc exec -n $NAMESPACE litemaas-postgres-0 -- \\"
    echo "    psql -U litemaas -d litemaas -c 'SELECT id, name FROM models;'"
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
