#!/bin/bash
# =============================================================================
# LiteMaaS Monitoring Setup Script
# =============================================================================
# Standalone script to deploy monitoring for existing LiteMaaS deployment
#
# Usage:
#   # Deploy monitoring
#   ./setup-monitoring.sh <namespace>
#
#   # Remove monitoring
#   ./setup-monitoring.sh <namespace> --remove
#
#   # With Icinga integration
#   ./setup-monitoring.sh <namespace> --icinga \
#     --icinga-url https://icinga.example.com/v1/events \
#     --icinga-user prometheus \
#     --icinga-pass secret
#
#   # Examples:
#     ./setup-monitoring.sh litellm-rhpds
#     ./setup-monitoring.sh litellm-rhpds --remove
#     ./setup-monitoring.sh litellm-rhpds --icinga --icinga-url https://icinga.example.com/v1/events
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
REMOVE_MODE=false
ICINGA_ENABLED=false
ICINGA_URL=""
ICINGA_USER=""
ICINGA_PASS=""
EXTRA_VARS=""

# Parse arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: Namespace is required${NC}"
    echo ""
    echo "Usage: $0 <namespace> [options]"
    echo ""
    echo "Options:"
    echo "  --remove                Remove monitoring setup"
    echo "  --icinga                Enable Icinga integration"
    echo "  --icinga-url <url>      Icinga API URL"
    echo "  --icinga-user <user>    Icinga API username"
    echo "  --icinga-pass <pass>    Icinga API password"
    echo ""
    echo "Examples:"
    echo "  $0 litellm-rhpds"
    echo "  $0 litellm-rhpds --remove"
    echo "  $0 litellm-rhpds --icinga --icinga-url https://icinga.example.com/v1/events"
    exit 1
fi

NAMESPACE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --remove)
            REMOVE_MODE=true
            shift
            ;;
        --icinga)
            ICINGA_ENABLED=true
            shift
            ;;
        --icinga-url)
            ICINGA_URL="$2"
            shift 2
            ;;
        --icinga-user)
            ICINGA_USER="$2"
            shift 2
            ;;
        --icinga-pass)
            ICINGA_PASS="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate Icinga parameters
if [ "$ICINGA_ENABLED" = true ]; then
    if [ -z "$ICINGA_URL" ] || [ -z "$ICINGA_USER" ] || [ -z "$ICINGA_PASS" ]; then
        echo -e "${RED}ERROR: Icinga integration requires --icinga-url, --icinga-user, and --icinga-pass${NC}"
        exit 1
    fi
fi

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
ANSIBLE_VARS="-e ocp4_workload_litemaas_monitoring_namespace=$NAMESPACE"

if [ "$REMOVE_MODE" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_monitoring_remove=true"
fi

if [ "$ICINGA_ENABLED" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_monitoring_icinga_enabled=true"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_monitoring_icinga_api_url=$ICINGA_URL"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_monitoring_icinga_api_username=$ICINGA_USER"
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_litemaas_monitoring_icinga_api_password=$ICINGA_PASS"
fi

# Display configuration
echo "========================================="
echo "LiteMaaS Monitoring Setup"
echo "========================================="
echo "Namespace:        $NAMESPACE"
echo "Remove Mode:      $REMOVE_MODE"
echo "Icinga:           $ICINGA_ENABLED"
if [ "$ICINGA_ENABLED" = true ]; then
    echo "  Icinga URL:     $ICINGA_URL"
    echo "  Icinga User:    $ICINGA_USER"
fi
echo ""

# Run playbook
echo "========================================="
if [ "$REMOVE_MODE" = true ]; then
    echo "Removing LiteMaaS monitoring..."
else
    echo "Setting up LiteMaaS monitoring..."
fi
echo "========================================="
echo ""

# Show command for transparency
echo "Running:"
echo "  ansible-playbook playbooks/setup_litemaas_monitoring.yml $ANSIBLE_VARS"
echo ""

if ansible-playbook playbooks/setup_litemaas_monitoring.yml $ANSIBLE_VARS; then
    echo ""
    echo "========================================="
    if [ "$REMOVE_MODE" = true ]; then
        echo -e "${GREEN}Monitoring Removal Complete!${NC}"
        echo "========================================="
        echo ""
        echo "Monitoring components removed from namespace: $NAMESPACE"
    else
        echo -e "${GREEN}Monitoring Setup Complete!${NC}"
        echo "========================================="
        echo ""

        # Get Grafana route
        GRAFANA_ROUTE=$(oc get route grafana -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

        echo "Access monitoring:"
        if [ -n "$GRAFANA_ROUTE" ]; then
            echo "  Grafana: https://$GRAFANA_ROUTE"
        fi
        echo ""
        echo "Verify setup:"
        echo "  # Check ServiceMonitor"
        echo "  oc get servicemonitors -n $NAMESPACE"
        echo ""
        echo "  # Check PrometheusRules"
        echo "  oc get prometheusrules -n $NAMESPACE"
        echo ""
        echo "  # Test metrics endpoint"
        echo "  oc port-forward -n $NAMESPACE svc/litellm 4000:4000"
        echo "  curl http://localhost:4000/metrics"
    fi
else
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Monitoring Setup Failed!${NC}"
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
