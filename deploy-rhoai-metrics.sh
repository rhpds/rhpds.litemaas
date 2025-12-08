#!/bin/bash
# =============================================================================
# RHOAI Metrics Dashboard Deployment Script
# =============================================================================
# Simple wrapper script to deploy RHOAI metrics monitoring using Ansible
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NAMESPACE="${NAMESPACE:-llm-hosting}"
ENABLE_GPU="${ENABLE_GPU:-true}"
RETENTION="${RETENTION:-7d}"
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-30s}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
print_header() {
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

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi
    print_info "✓ oc CLI found"

    # Check ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook not found. Please install Ansible."
        exit 1
    fi
    print_info "✓ ansible-playbook found"

    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster. Run 'oc login' first."
        exit 1
    fi
    print_info "✓ Logged into OpenShift cluster as $(oc whoami)"

    # Check namespace exists
    if ! oc get namespace "${NAMESPACE}" &> /dev/null; then
        print_warn "Namespace ${NAMESPACE} does not exist. Creating it..."
        oc create namespace "${NAMESPACE}"
    fi
    print_info "✓ Namespace ${NAMESPACE} exists"
}

check_gpu_operator() {
    if [ "${ENABLE_GPU}" = "true" ]; then
        print_info "Checking for NVIDIA GPU Operator..."
        if oc get namespace nvidia-gpu-operator &> /dev/null; then
            print_info "✓ GPU Operator found - GPU metrics will be enabled"
        else
            print_warn "GPU Operator not found - GPU metrics will be disabled"
            ENABLE_GPU="false"
        fi
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
        name: rhpds.litemaas.ocp4_workload_rhoai_metrics
      vars:
        ocp4_workload_rhoai_metrics_namespace: "${NAMESPACE}"
        ocp4_workload_rhoai_metrics_enable_gpu: ${ENABLE_GPU}
        ocp4_workload_rhoai_metrics_uwm_retention: "${RETENTION}"
        ocp4_workload_rhoai_metrics_scrape_interval: "${SCRAPE_INTERVAL}"
EOF

    print_info "Running Ansible playbook..."
    ansible-playbook "${TEMP_PLAYBOOK}"

    # Clean up
    rm -f "${TEMP_PLAYBOOK}"
}

get_grafana_url() {
    print_header "Getting Grafana Access Information"

    print_info "Waiting for Grafana route..."
    for i in {1..30}; do
        if GRAFANA_URL=$(oc get route rhoai-grafana-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null); then
            if [ -n "${GRAFANA_URL}" ]; then
                print_info "✓ Grafana is ready!"
                echo ""
                print_header "Access Information"
                echo ""
                echo -e "${GREEN}Grafana URL:${NC} https://${GRAFANA_URL}"
                echo -e "${GREEN}Namespace:${NC} ${NAMESPACE}"
                echo -e "${GREEN}Login:${NC} Use OpenShift OAuth (your cluster credentials)"
                echo ""
                echo -e "${GREEN}Available Dashboards:${NC}"
                echo "  • vLLM - Model Metrics"
                echo "  • vLLM - Service Performance"
                echo "  • OpenVino - Model Metrics"
                echo "  • OpenVino - Service Performance"
                echo ""
                return 0
            fi
        fi
        sleep 10
    done

    print_warn "Grafana route not found yet. Check manually with:"
    echo "  oc get route rhoai-grafana-route -n ${NAMESPACE}"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy RHOAI Metrics Dashboard for monitoring AI model serving workloads.

Options:
  -n, --namespace NAMESPACE   Model serving namespace (default: llm-hosting)
  -g, --enable-gpu BOOL       Enable GPU metrics (default: true)
  -r, --retention DURATION    Metrics retention period (default: 7d)
  -s, --scrape-interval TIME  Prometheus scrape interval (default: 30s)
  -h, --help                  Show this help message

Environment Variables:
  NAMESPACE                   Same as --namespace
  ENABLE_GPU                  Same as --enable-gpu
  RETENTION                   Same as --retention
  SCRAPE_INTERVAL             Same as --scrape-interval

Examples:
  # Deploy with defaults
  $0

  # Deploy to custom namespace
  $0 --namespace my-models

  # Deploy without GPU metrics
  $0 --enable-gpu false

  # Deploy with 14-day retention
  $0 --retention 14d

  # Use environment variables
  export NAMESPACE=llm-hosting
  export ENABLE_GPU=true
  $0

What Gets Deployed:
  • OpenShift User Workload Monitoring
  • Grafana Operator (if not installed)
  • Grafana instance with pre-configured dashboards
  • ServiceMonitors for vLLM and OpenVino models
  • GPU metrics collection (if GPU Operator is present)

Prerequisites:
  • OpenShift 4.10+ cluster
  • OpenShift AI 2.10+ with KServe
  • oc CLI logged into cluster
  • Ansible 2.9+ with kubernetes.core collection

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

    print_header "RHOAI Metrics Dashboard Deployment"
    echo ""
    echo -e "${GREEN}Configuration:${NC}"
    echo "  Namespace:       ${NAMESPACE}"
    echo "  GPU Monitoring:  ${ENABLE_GPU}"
    echo "  Retention:       ${RETENTION}"
    echo "  Scrape Interval: ${SCRAPE_INTERVAL}"
    echo ""

    check_prerequisites
    check_gpu_operator
    deploy_metrics
    get_grafana_url

    print_header "Deployment Complete!"
    print_info "RHOAI Metrics Dashboard is ready to use"
}

# Run main function
main "$@"
