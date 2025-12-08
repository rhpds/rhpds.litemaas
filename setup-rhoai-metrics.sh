#!/bin/bash
# =============================================================================
# RHOAI Metrics Setup Script
# =============================================================================
# Enable RHOAI User Workload Metrics for Single Serving Models and deploy
# Grafana dashboards to monitor vLLM, OpenVino, and other model runtimes
#
# Usage:
#   # Deploy RHOAI metrics
#   ./setup-rhoai-metrics.sh <namespace>
#
#   # Deploy with GPU monitoring
#   ./setup-rhoai-metrics.sh <namespace> --gpu
#
#   # Remove RHOAI metrics
#   ./setup-rhoai-metrics.sh <namespace> --remove
#
#   # Examples:
#     ./setup-rhoai-metrics.sh llm-hosting
#     ./setup-rhoai-metrics.sh llm-hosting --gpu
#     ./setup-rhoai-metrics.sh llm-hosting --remove
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
ENABLE_GPU=false
EXTRA_VARS=""

# Parse arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: Namespace is required${NC}"
    echo ""
    echo "Usage: $0 <namespace> [options]"
    echo ""
    echo "Options:"
    echo "  --gpu                   Enable GPU monitoring (requires NVIDIA GPU Operator)"
    echo "  --remove                Remove RHOAI metrics setup"
    echo ""
    echo "Examples:"
    echo "  $0 llm-hosting"
    echo "  $0 llm-hosting --gpu"
    echo "  $0 llm-hosting --remove"
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
        --gpu)
            ENABLE_GPU=true
            shift
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
ANSIBLE_VARS="-e ocp4_workload_rhoai_metrics_namespace=$NAMESPACE"

if [ "$REMOVE_MODE" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_rhoai_metrics_remove=true"
fi

if [ "$ENABLE_GPU" = true ]; then
    ANSIBLE_VARS="$ANSIBLE_VARS -e ocp4_workload_rhoai_metrics_enable_gpu=true"
fi

# Display configuration
echo "========================================="
echo "RHOAI Metrics Setup"
echo "========================================="
echo "Namespace:        $NAMESPACE"
echo "Remove Mode:      $REMOVE_MODE"
echo "GPU Monitoring:   $ENABLE_GPU"
echo ""

# Run playbook
echo "========================================="
if [ "$REMOVE_MODE" = true ]; then
    echo "Removing RHOAI metrics..."
else
    echo "Setting up RHOAI metrics..."
fi
echo "========================================="
echo ""

# Show command for transparency
echo "Running:"
echo "  ansible-playbook playbooks/setup_rhoai_metrics.yml $ANSIBLE_VARS"
echo ""

if ansible-playbook playbooks/setup_rhoai_metrics.yml $ANSIBLE_VARS; then
    echo ""
    echo "========================================="
    if [ "$REMOVE_MODE" = true ]; then
        echo -e "${GREEN}RHOAI Metrics Removal Complete!${NC}"
        echo "========================================="
        echo ""
        echo "All monitoring resources removed from namespace: $NAMESPACE"
    else
        echo -e "${GREEN}RHOAI Metrics Setup Complete!${NC}"
        echo "========================================="
        echo ""

        # Get Grafana route
        GRAFANA_ROUTE=$(oc get route rhoai-grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

        echo "Access Grafana dashboards:"
        if [ -n "$GRAFANA_ROUTE" ]; then
            echo "  Grafana: https://$GRAFANA_ROUTE"
        fi
        echo ""
        echo "Dashboards available:"
        echo "  • vLLM Model Metrics"
        echo "  • vLLM Service Performance"
        echo "  • OpenVino Model Metrics"
        echo "  • OpenVino Service Performance"
        if [ "$ENABLE_GPU" = true ]; then
            echo "  • NVIDIA DCGM Exporter (GPU metrics)"
        fi
        echo ""
        echo "Verify setup:"
        echo "  # Check ServiceMonitors"
        echo "  oc get servicemonitors -n $NAMESPACE"
        echo ""
        echo "  # Check Grafana dashboards"
        echo "  oc get grafanadashboards -n $NAMESPACE"
        echo ""
        echo "  # Check User Workload Monitoring"
        echo "  oc get pods -n openshift-user-workload-monitoring"
    fi
else
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}RHOAI Metrics Setup Failed!${NC}"
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
