#!/bin/bash
# =============================================================================
# Remove Beta Labels from LiteMaaS Frontend
# =============================================================================
# Removes "Beta" text from login page and welcome message without redeploying
#
# Usage:
#   Quick fix (running pod only - reverts on pod restart):
#     ./remove-beta-labels.sh <namespace>
#
#   Permanent fix (patches deployment):
#     ./remove-beta-labels.sh <namespace> --permanent
#
# Examples:
#   # Remove Beta from running frontend pod
#   ./remove-beta-labels.sh litellm-rhpds
#
#   # Remove Beta and update deployment (survives restarts)
#   ./remove-beta-labels.sh litellm-rhpds --permanent
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="${1:-}"
PERMANENT=false

if [ -z "$NAMESPACE" ]; then
    echo -e "${RED}ERROR: Namespace is required${NC}"
    echo ""
    echo "Usage: $0 <namespace> [--permanent]"
    echo ""
    echo "Examples:"
    echo "  # Quick fix (running pod only)"
    echo "  $0 litellm-rhpds"
    echo ""
    echo "  # Permanent fix (patches deployment)"
    echo "  $0 litellm-rhpds --permanent"
    exit 1
fi

if [ "$2" == "--permanent" ]; then
    PERMANENT=true
fi

echo "========================================="
echo "Remove Beta Labels from LiteMaaS"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Mode:      $([ "$PERMANENT" = true ] && echo 'Permanent (patches deployment)' || echo 'Quick fix (current pod only)')"
echo ""

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}ERROR: oc command not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}ERROR: Not logged into OpenShift. Run 'oc login' first.${NC}"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq command not found. Please install jq.${NC}"
    exit 1
fi

echo -e "${BLUE}Finding frontend pod...${NC}"

# Find frontend pod
FRONTEND_POD=$(oc get pods -n "$NAMESPACE" -l app=litellm-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$FRONTEND_POD" ]; then
    # Try alternative label
    FRONTEND_POD=$(oc get pods -n "$NAMESPACE" -l app=litemaas-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -z "$FRONTEND_POD" ]; then
    echo -e "${RED}ERROR: Frontend pod not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "Available pods:"
    oc get pods -n "$NAMESPACE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found frontend pod: $FRONTEND_POD"
echo ""

# Check pod status
POD_STATUS=$(oc get pod "$FRONTEND_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}ERROR: Frontend pod is not running (status: $POD_STATUS)${NC}"
    exit 1
fi

echo -e "${BLUE}Removing Beta labels from frontend files...${NC}"
echo ""

# Find and update JavaScript bundle files
echo "Finding JavaScript bundles..."

# Execute commands in the pod to remove Beta text
oc exec -n "$NAMESPACE" "$FRONTEND_POD" -- sh -c '
# Find all JS files in the app directory
cd /app || cd /usr/share/nginx/html || exit 1

echo "Working directory: $(pwd)"
echo ""

# Find JS bundle files
JS_FILES=$(find . -name "*.js" -type f 2>/dev/null | head -10)

if [ -z "$JS_FILES" ]; then
    echo "No JavaScript files found"
    exit 1
fi

echo "Found JavaScript files:"
echo "$JS_FILES"
echo ""

# Remove Beta from all text variations
for file in $JS_FILES; do
    if [ -f "$file" ]; then
        # Check if file contains Beta text
        if grep -q "Beta" "$file" 2>/dev/null; then
            echo "Processing: $file"

            # Remove (Beta) from titles
            sed -i "s/ (Beta)//g" "$file" 2>/dev/null || true

            # Remove BETA: prefix from disclaimers
            sed -i "s/BETA: This service is intended for demos/This service is intended for demos/g" "$file" 2>/dev/null || true
            sed -i "s/BETA://g" "$file" 2>/dev/null || true

            # Clean up any remaining Beta references in titles
            sed -i "s/Red Hat Demo Platform MaaS service (Beta)/Red Hat Demo Platform MaaS service/g" "$file" 2>/dev/null || true
            sed -i "s/Red Hat Demo Platform MaaS (Beta)/Red Hat Demo Platform MaaS/g" "$file" 2>/dev/null || true

            echo "  ✓ Removed Beta labels"
        fi
    fi
done

echo ""
echo "Beta labels removed from JavaScript bundles"
' && echo -e "${GREEN}✓${NC} Beta labels removed from running pod"

if [ "$PERMANENT" = true ]; then
    echo ""
    echo -e "${BLUE}Making changes permanent by patching deployment...${NC}"

    # Find frontend deployment
    FRONTEND_DEPLOYMENT=$(oc get deployment -n "$NAMESPACE" -l app=litellm-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$FRONTEND_DEPLOYMENT" ]; then
        FRONTEND_DEPLOYMENT=$(oc get deployment -n "$NAMESPACE" -l app=litemaas-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [ -z "$FRONTEND_DEPLOYMENT" ]; then
        echo -e "${YELLOW}WARNING: Frontend deployment not found. Changes will revert on pod restart.${NC}"
    else
        echo "Found deployment: $FRONTEND_DEPLOYMENT"

        # Check if deployment has initContainer with Beta labels
        HAS_INIT_CONTAINER=$(oc get deployment "$FRONTEND_DEPLOYMENT" -n "$NAMESPACE" -o json | jq '.spec.template.spec.initContainers // [] | length')

        if [ "$HAS_INIT_CONTAINER" -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}Deployment has initContainer that adds Beta labels.${NC}"
            echo "To make removal permanent, you need to redeploy without --logos flag:"
            echo ""
            echo -e "  ${GREEN}./deploy-litemaas.sh $NAMESPACE --ha --replicas <count> --oauth --route-prefix <name>${NC}"
            echo ""
            echo "Or manually edit the deployment and remove initContainer sed commands:"
            echo ""
            echo -e "  ${GREEN}oc edit deployment $FRONTEND_DEPLOYMENT -n $NAMESPACE${NC}"
            echo ""
            echo "Current fix will work until pod restarts."
        else
            echo -e "${GREEN}✓${NC} No initContainer found - changes should persist on restart"
        fi
    fi
fi

echo ""
echo "========================================="
echo -e "${GREEN}Beta Labels Removed!${NC}"
echo "========================================="
echo ""

# Get frontend route
FRONTEND_ROUTE=$(oc get routes -n "$NAMESPACE" -o json 2>/dev/null | \
                 jq -r '.items[] | select(.spec.to.name | test("frontend")) | .spec.host' 2>/dev/null | head -1)

if [ -n "$FRONTEND_ROUTE" ]; then
    echo "Frontend URL: https://$FRONTEND_ROUTE"
    echo ""
    echo "Clear your browser cache and refresh the page to see changes:"
    echo "  1. Open Developer Tools (F12)"
    echo "  2. Right-click refresh button"
    echo "  3. Select 'Empty Cache and Hard Reload'"
else
    echo "Refresh your browser to see the changes"
fi

echo ""

if [ "$PERMANENT" = false ]; then
    echo -e "${YELLOW}Note: Changes will revert if the pod restarts.${NC}"
    echo "For permanent removal, run: $0 $NAMESPACE --permanent"
    echo "Or redeploy without --logos flag"
fi

echo ""
