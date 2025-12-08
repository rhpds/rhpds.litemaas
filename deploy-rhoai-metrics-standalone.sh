#!/bin/bash
# =============================================================================
# RHOAI Metrics Dashboard Deployment Script (Standalone)
# =============================================================================
# Self-contained script that installs all dependencies and deploys RHOAI metrics
# Creates Python venv, installs Ansible, and runs deployment
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NAMESPACE="${NAMESPACE:-llm-hosting}"
ENABLE_GPU="${ENABLE_GPU:-true}"
RETENTION="${RETENTION:-7d}"
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-30s}"

# Virtual environment
VENV_DIR="${VENV_DIR:-.venv-rhoai-metrics}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_python() {
    print_header "Checking Python"

    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        print_info "✓ Python 3 found: ${PYTHON_VERSION}"
        PYTHON_CMD="python3"
    else
        print_error "Python 3 not found. Please install Python 3.8 or later."
        exit 1
    fi
}

check_oc_cli() {
    print_header "Checking OpenShift CLI"

    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found. Please install OpenShift CLI."
        echo ""
        echo "Install from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
        exit 1
    fi
    print_info "✓ oc CLI found: $(oc version --client | head -1)"

    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster."
        echo ""
        echo "Please run: oc login <cluster-url>"
        exit 1
    fi
    print_info "✓ Logged into OpenShift as $(oc whoami)"
}

check_git() {
    print_header "Checking Git"

    if ! command -v git &> /dev/null; then
        print_error "git command not found. Please install git."
        echo ""
        echo "Install git:"
        echo "  RHEL/Fedora: sudo dnf install git"
        echo "  Ubuntu/Debian: sudo apt-get install git"
        echo "  macOS: brew install git"
        exit 1
    fi
    print_info "✓ git found: $(git --version)"
}

create_or_activate_venv() {
    print_header "Setting Up Python Virtual Environment"

    # Force reinstall if requested
    if [ "${FORCE_REINSTALL}" = "true" ] && [ -d "${VENV_DIR}" ]; then
        print_warn "Force reinstall requested"
        print_step "Removing existing virtual environment..."
        rm -rf "${VENV_DIR}"
    fi

    if [ -d "${VENV_DIR}" ]; then
        print_info "Virtual environment already exists at ${VENV_DIR}"
        print_info "Reusing existing virtual environment (use --force-reinstall to recreate)"

        # Activate existing venv
        source "${VENV_DIR}/bin/activate"
        print_info "✓ Virtual environment activated"

        # Check if ansible is installed
        if command -v ansible-playbook &> /dev/null; then
            print_info "✓ Ansible already installed: $(ansible --version | head -1 | cut -d' ' -f3)"
            VENV_EXISTS_WITH_DEPS=true
        else
            print_warn "Ansible not found in venv, will reinstall dependencies"
            VENV_EXISTS_WITH_DEPS=false
        fi
    else
        print_step "Creating new virtual environment..."
        ${PYTHON_CMD} -m venv "${VENV_DIR}"
        print_info "✓ Virtual environment created"

        # Activate venv
        source "${VENV_DIR}/bin/activate"
        print_info "✓ Virtual environment activated"

        # Upgrade pip
        print_step "Upgrading pip..."
        pip install --quiet --upgrade pip
        print_info "✓ pip upgraded to $(pip --version | cut -d' ' -f2)"

        VENV_EXISTS_WITH_DEPS=false
    fi
}

install_python_deps() {
    print_header "Installing Python Dependencies"

    # Skip if dependencies already exist
    if [ "${VENV_EXISTS_WITH_DEPS:-false}" = "true" ]; then
        print_info "Dependencies already installed, skipping..."
        return 0
    fi

    print_step "Installing Ansible and required libraries..."
    pip install --quiet \
        ansible \
        kubernetes \
        openshift \
        gitpython \
        jinja2 \
        pyyaml

    print_info "✓ Ansible $(ansible --version | head -1 | cut -d' ' -f3) installed"
    print_info "✓ GitPython installed (for ansible.builtin.git module)"
    print_info "✓ Python dependencies installed"
}

install_ansible_collections() {
    print_header "Installing Ansible Collections"

    # Skip if dependencies already exist
    if [ "${VENV_EXISTS_WITH_DEPS:-false}" = "true" ]; then
        print_info "Ansible collections already installed, skipping..."
        return 0
    fi

    print_step "Installing kubernetes.core collection..."
    ansible-galaxy collection install kubernetes.core --force

    print_info "✓ kubernetes.core collection installed"

    # Show installed collections
    print_info "Installed collections:"
    ansible-galaxy collection list | grep -E "kubernetes|openshift" || true
}

check_namespace() {
    print_header "Checking Target Namespace"

    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        print_info "✓ Namespace ${NAMESPACE} exists"
    else
        print_warn "Namespace ${NAMESPACE} does not exist"
        print_step "Creating namespace..."
        oc create namespace "${NAMESPACE}"
        print_info "✓ Namespace ${NAMESPACE} created"
    fi
}

check_gpu_operator() {
    print_header "Checking GPU Operator"

    if [ "${ENABLE_GPU}" = "true" ]; then
        if oc get namespace nvidia-gpu-operator &> /dev/null; then
            print_info "✓ NVIDIA GPU Operator found"
            print_info "  GPU metrics will be enabled"
        else
            print_warn "NVIDIA GPU Operator not found"
            print_info "  GPU metrics will be disabled"
            ENABLE_GPU="false"
        fi
    else
        print_info "GPU metrics disabled (ENABLE_GPU=false)"
    fi
}

deploy_metrics() {
    print_header "Deploying RHOAI Metrics Dashboard"

    # Create temporary playbook
    TEMP_PLAYBOOK=$(mktemp /tmp/rhoai-metrics-XXXXX.yml)

    cat > "${TEMP_PLAYBOOK}" <<EOF
---
- name: Deploy RHOAI Metrics Dashboard
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Deploy RHOAI metrics monitoring
      ansible.builtin.include_role:
        name: ocp4_workload_rhoai_metrics
      vars:
        ocp4_workload_rhoai_metrics_namespace: "${NAMESPACE}"
        ocp4_workload_rhoai_metrics_enable_gpu: ${ENABLE_GPU}
        ocp4_workload_rhoai_metrics_uwm_retention: "${RETENTION}"
        ocp4_workload_rhoai_metrics_scrape_interval: "${SCRAPE_INTERVAL}"
EOF

    print_step "Running Ansible playbook..."
    echo ""

    # Run ansible-playbook from the script directory
    cd "${SCRIPT_DIR}"

    ANSIBLE_ROLES_PATH="${SCRIPT_DIR}/roles" \
    ANSIBLE_COLLECTIONS_PATH="${VENV_DIR}/lib/python*/site-packages/ansible_collections" \
    ansible-playbook "${TEMP_PLAYBOOK}" -v

    # Clean up
    rm -f "${TEMP_PLAYBOOK}"

    print_info "✓ Deployment completed"
}

get_grafana_url() {
    print_header "Getting Grafana Access Information"

    print_step "Waiting for Grafana route..."
    for i in {1..30}; do
        if GRAFANA_URL=$(oc get route rhoai-grafana-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null); then
            if [ -n "${GRAFANA_URL}" ]; then
                echo ""
                print_header "🎉 Deployment Successful!"
                echo ""
                echo -e "${GREEN}Grafana URL:${NC} https://${GRAFANA_URL}"
                echo -e "${GREEN}Namespace:${NC} ${NAMESPACE}"
                echo -e "${GREEN}Login:${NC} Use OpenShift OAuth (your cluster credentials)"
                echo ""
                echo -e "${GREEN}Available Dashboards:${NC}"
                echo "  📊 vLLM - Model Metrics"
                echo "  📈 vLLM - Service Performance"
                echo "  📊 OpenVino - Model Metrics"
                echo "  📈 OpenVino - Service Performance"
                if [ "${ENABLE_GPU}" = "true" ]; then
                    echo "  🎮 NVIDIA DCGM - GPU Metrics"
                fi
                echo ""
                echo -e "${GREEN}Next Steps:${NC}"
                echo "  1. Open Grafana: https://${GRAFANA_URL}"
                echo "  2. Login with your OpenShift credentials"
                echo "  3. Navigate to Dashboards to view metrics"
                echo ""
                return 0
            fi
        fi
        sleep 10
        echo -n "."
    done
    echo ""

    print_warn "Grafana route not found yet"
    print_info "Check manually with:"
    echo "  oc get route rhoai-grafana-route -n ${NAMESPACE}"
}

cleanup_venv() {
    if [ "${CLEANUP_VENV:-false}" = "true" ]; then
        print_header "Cleaning Up"
        print_step "Removing virtual environment..."
        deactivate 2>/dev/null || true
        rm -rf "${VENV_DIR}"
        print_info "✓ Virtual environment removed"
    else
        print_info "Virtual environment kept at: ${VENV_DIR}"
        print_info "To activate later: source ${VENV_DIR}/bin/activate"
    fi
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Self-contained deployment script for RHOAI Metrics Dashboard.
Automatically installs Python venv, Ansible, and all dependencies.

Options:
  -n, --namespace NAMESPACE   Model serving namespace (default: llm-hosting)
  -g, --enable-gpu BOOL       Enable GPU metrics (default: true)
  -r, --retention DURATION    Metrics retention period (default: 7d)
  -s, --scrape-interval TIME  Prometheus scrape interval (default: 30s)
  -f, --force-reinstall       Force reinstall venv and dependencies
  -c, --cleanup               Remove Python venv after deployment
  -h, --help                  Show this help message

Environment Variables:
  NAMESPACE                   Same as --namespace
  ENABLE_GPU                  Same as --enable-gpu
  RETENTION                   Same as --retention
  SCRAPE_INTERVAL             Same as --scrape-interval
  VENV_DIR                    Python venv directory (default: .venv-rhoai-metrics)
  CLEANUP_VENV                Same as --cleanup

Examples:
  # Deploy with defaults (reuses existing venv if present)
  $0

  # Deploy to custom namespace
  $0 --namespace my-models

  # Deploy without GPU metrics
  $0 --enable-gpu false

  # Force reinstall venv (if dependencies are broken)
  $0 --force-reinstall

  # Deploy and cleanup venv after
  $0 --cleanup

  # Use custom venv location
  VENV_DIR=/tmp/venv $0

What This Script Does:
  1. ✓ Checks Python 3 and oc CLI
  2. ✓ Creates/reuses Python virtual environment
  3. ✓ Installs Ansible and dependencies (pip) - only if needed
  4. ✓ Installs kubernetes.core collection - only if needed
  5. ✓ Checks/creates target namespace
  6. ✓ Detects GPU Operator presence
  7. ✓ Deploys RHOAI metrics monitoring
  8. ✓ Retrieves Grafana access URL

Performance:
  • First run: ~2-3 minutes (installs dependencies)
  • Subsequent runs: ~30 seconds (reuses venv)

Prerequisites:
  • Python 3.8+ installed
  • oc CLI installed and logged into cluster
  • Internet access (for pip packages)

For more information:
  https://github.com/rhpds/rhpds.litemaas
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -g|--enable-gpu)
                ENABLE_GPU="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION="$2"
                shift 2
                ;;
            -s|--scrape-interval)
                SCRAPE_INTERVAL="$2"
                shift 2
                ;;
            -f|--force-reinstall)
                FORCE_REINSTALL="true"
                shift
                ;;
            -c|--cleanup)
                CLEANUP_VENV="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_header "🚀 RHOAI Metrics Dashboard - Standalone Deployment"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  Namespace:        ${NAMESPACE}"
    echo "  GPU Monitoring:   ${ENABLE_GPU}"
    echo "  Retention:        ${RETENTION}"
    echo "  Scrape Interval:  ${SCRAPE_INTERVAL}"
    echo "  Venv Directory:   ${VENV_DIR}"
    echo ""

    # Run deployment steps
    check_python
    check_git
    check_oc_cli
    create_or_activate_venv
    install_python_deps
    install_ansible_collections
    check_namespace
    check_gpu_operator
    deploy_metrics
    get_grafana_url
    cleanup_venv

    print_header "✅ All Done!"
}

# Trap errors
trap 'print_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
