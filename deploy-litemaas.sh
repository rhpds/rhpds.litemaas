#!/bin/bash
# =============================================================================
# LiteMaaS Deployment Script
# =============================================================================
# Deploys LiteMaaS in High Availability mode with automatic Python venv setup
#
# Usage:
#   # Standard HA deployment
#   ./deploy-litemaas.sh <namespace>
#
#   # HA with RHDP branding
#   ./deploy-litemaas.sh <namespace> --rhdp
#
#   # Custom replicas
#   ./deploy-litemaas.sh <namespace> --replicas 5
#
#   # With OAuth and custom route prefix
#   ./deploy-litemaas.sh <namespace> --oauth --route-prefix litellm-prod
#
#   # Remove deployment
#   ./deploy-litemaas.sh <namespace> --remove
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

# Default values
NAMESPACE=""
HA_REPLICAS=3
REMOVE_MODE=false
EXTRA_VARS=""

# Feature flags
ENABLE_OAUTH=false
ENABLE_RHDP=false
ROUTE_PREFIX=""

# Parse arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: Namespace is required${NC}"
    echo ""
    echo "Usage: $0 <namespace> [options]"
    echo ""
    echo "Options:"
    echo "  --replicas <count>    Number of LiteLLM replicas (default: 3)"
    echo "  --remove              Remove existing deployment"
    echo "  --oauth               Enable OAuth authentication with OpenShift"
    echo "  --rhdp                Enable RHDP branding (logos + footer)"
    echo "  --route-prefix <name> Set custom route prefix (e.g., litellm-prod)"
    echo "  -e <key=value>        Pass extra variables to Ansible"
    echo ""
    echo "Examples:"
    echo "  # Standard HA deployment"
    echo "  $0 litellm-rhpds"
    echo ""
    echo "  # HA with RHDP branding"
    echo "  $0 litellm-rhpds --rhdp"
    echo ""
    echo "  # Full RHDP production (OAuth + branding + custom routes)"
    echo "  $0 litellm-rhpds --oauth --rhdp --route-prefix litellm-prod"
    echo ""
    echo "  # Remove deployment"
    echo "  $0 litellm-rhpds --remove"
    exit 1
fi

NAMESPACE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --replicas)
            HA_REPLICAS="$2"
            shift 2
            ;;
        --remove)
            REMOVE_MODE=true
            shift
            ;;
        --oauth)
            ENABLE_OAUTH=true
            shift
            ;;
        --rhdp)
            ENABLE_RHDP=true
            shift
            ;;
        --route-prefix)
            ROUTE_PREFIX="$2"
            shift 2
            ;;
        -e)
            EXTRA_VARS="$EXTRA_VARS -e $2"
            shift 2
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

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

echo -e "${GREEN}✓${NC} OpenShift CLI found and authenticated"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: python3 command not found. Please install Python 3.${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo -e "${GREEN}✓${NC} Python 3 found (version: $PYTHON_VERSION)"
echo ""

# Setup Python virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✓${NC} Virtual environment created at $VENV_DIR"
else
    echo -e "${GREEN}✓${NC} Virtual environment already exists at $VENV_DIR"
fi
echo ""

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
echo -e "${GREEN}✓${NC} Virtual environment activated"
echo ""

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip --quiet
echo -e "${GREEN}✓${NC} pip upgraded"
echo ""

# Install Ansible and dependencies
echo "Installing Ansible and dependencies..."
if ! pip show ansible &> /dev/null || ! pip show kubernetes &> /dev/null; then
    pip install ansible kubernetes --quiet
    echo -e "${GREEN}✓${NC} Ansible and dependencies installed"
else
    echo -e "${GREEN}✓${NC} Ansible and dependencies already installed"
fi

ANSIBLE_VERSION=$(ansible --version | head -1)
echo "  $ANSIBLE_VERSION"
echo ""

# Build collection
echo "Building Ansible collection..."
cd "$SCRIPT_DIR"
ansible-galaxy collection build --force
COLLECTION_FILE=$(ls rhpds-litemaas-*.tar.gz | sort -V | tail -1)
echo -e "${GREEN}✓${NC} Collection built: $COLLECTION_FILE"
echo ""

# Install collection
echo "Installing Ansible collection..."
ansible-galaxy collection install "$COLLECTION_FILE" --force
echo -e "${GREEN}✓${NC} Collection installed"
echo ""

# Prepare Ansible variables
ANSIBLE_VARS="-e ocp4_workload_litemaas_namespace=$NAMESPACE"
ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_ha_litellm_replicas=$HA_REPLICAS"
PLAYBOOK="playbooks/deploy_litemaas_ha.yml"

if [ "$REMOVE_MODE" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_remove=true"
fi

# Display deployment configuration
echo "========================================="
echo "LiteMaaS HA Deployment"
echo "========================================="
echo "Namespace:        $NAMESPACE"
echo "HA Replicas:      $HA_REPLICAS"
echo "Remove Mode:      $REMOVE_MODE"
echo ""
echo "Features:"
echo "  OAuth:          $ENABLE_OAUTH"
echo "  RHDP Branding:  $ENABLE_RHDP"
if [ -n "$ROUTE_PREFIX" ]; then
    echo "  Route Prefix:   $ROUTE_PREFIX"
fi
echo ""

# Add feature flags
if [ "$ENABLE_OAUTH" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_oauth_enabled=true"
fi

# Backend and frontend always enabled in HA
ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_deploy_backend=true"
ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_deploy_frontend=true"

if [ "$ENABLE_RHDP" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_branding_enabled=true"
fi

if [ -n "$ROUTE_PREFIX" ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_api_route_prefix=$ROUTE_PREFIX"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_admin_route_prefix=${ROUTE_PREFIX}-admin"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_frontend_route_prefix=${ROUTE_PREFIX}-frontend"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_api_route_name=$ROUTE_PREFIX"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_admin_route_name=${ROUTE_PREFIX}-admin"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_frontend_route_name=${ROUTE_PREFIX}-frontend"
fi

# Add extra variables
ANSIBLE_VARS="$ANSIBLE_VARS $EXTRA_VARS"

# Run deployment
echo "========================================="
if [ "$REMOVE_MODE" = true ]; then
    echo "Removing LiteMaaS deployment..."
else
    echo "Deploying LiteMaaS..."
fi
echo "========================================="
echo ""

# Show command for transparency
echo "Running:"
echo "  ansible-playbook $PLAYBOOK $ANSIBLE_VARS"
echo ""

if ansible-playbook "$PLAYBOOK" $ANSIBLE_VARS; then
    echo ""
    echo "========================================="
    if [ "$REMOVE_MODE" = true ]; then
        echo -e "${GREEN}Removal Complete!${NC}"
        echo "========================================="
        echo ""
        echo "LiteMaaS has been removed from namespace: $NAMESPACE"
    else
        echo -e "${GREEN}Deployment Complete!${NC}"
        echo "========================================="
        echo ""

        # Wait a moment for routes to be ready
        sleep 2

        # Get the LiteLLM route
        LITELLM_ROUTE=$(oc get routes -n "$NAMESPACE" -o json 2>/dev/null | \
                        jq -r '.items[] | select(.spec.to.name == "litellm") | .spec.host' 2>/dev/null | head -1)

        if [ -n "$LITELLM_ROUTE" ]; then
            echo -e "${GREEN}Access LiteMaaS:${NC}"
            echo "  API URL: https://$LITELLM_ROUTE"
            echo ""
        fi

        echo "Get admin credentials:"
        echo "  # Master API Key"
        echo "  oc get secret -n $NAMESPACE -o json | jq -r '.items[] | select(.data.LITELLM_MASTER_KEY != null) | .data.LITELLM_MASTER_KEY' | base64 -d"
        echo ""
        echo "  # Admin Password (if OAuth enabled)"
        echo "  oc get secret backend-secret -n $NAMESPACE -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d"
        echo ""

        echo -e "${YELLOW}High Availability:${NC}"
        echo "  LiteLLM replicas: $HA_REPLICAS"
        echo ""

        echo "Next steps:"
        echo "  1. Get the master API key using command above"
        echo "  2. Add models via LiteLLM admin UI or playbook"
    fi
else
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Deployment Failed!${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "Check the output above for error details."
    exit 1
fi

# Deactivate venv
deactivate

echo ""
echo "Virtual environment deactivated."
echo ""
