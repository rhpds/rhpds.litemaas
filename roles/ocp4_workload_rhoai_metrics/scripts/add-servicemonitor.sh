#!/bin/bash
# =============================================================================
# Add ServiceMonitor for RHOAI Model
# =============================================================================
# Creates a ServiceMonitor resource for monitoring vLLM or OpenVino models
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $0 <model-name> <namespace> [options]

Add ServiceMonitor for a vLLM or OpenVino model.

Arguments:
  model-name              Name of the InferenceService
  namespace               Namespace where the model is deployed

Options:
  --interval INTERVAL     Scrape interval (default: 30s)
  --timeout TIMEOUT       Scrape timeout (default: 10s)
  --path PATH             Metrics path (default: /metrics)
  --port PORT             Metrics port name (default: http)
  --runtime RUNTIME       Runtime type: vllm or openvino (default: vllm)
  -h, --help              Show this help message

Examples:
  # Add ServiceMonitor for vLLM model
  $0 llama-3-2-1b-fp8 llm-hosting

  # Add ServiceMonitor for OpenVino model
  $0 my-openvino-model llm-hosting --runtime openvino

  # Custom scrape interval
  $0 granite-3-2-8b-instruct llm-hosting --interval 15s
EOF
}

# Default values
INTERVAL="30s"
TIMEOUT="10s"
PATH="/metrics"
PORT="http"
RUNTIME="vllm"

# Parse arguments
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

MODEL_NAME="$1"
NAMESPACE="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --path)
            PATH="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --runtime)
            RUNTIME="$2"
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

# Validate runtime
if [[ ! "$RUNTIME" =~ ^(vllm|openvino)$ ]]; then
    print_error "Runtime must be 'vllm' or 'openvino'"
    exit 1
fi

# Check if oc CLI is available
if ! command -v oc &> /dev/null; then
    print_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    print_error "Not logged into OpenShift cluster. Run 'oc login' first."
    exit 1
fi

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace $NAMESPACE does not exist"
    exit 1
fi

# Check if InferenceService exists
if ! oc get inferenceservice "$MODEL_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_warn "InferenceService $MODEL_NAME not found in namespace $NAMESPACE"
    print_warn "ServiceMonitor will be created but won't have targets until the model is deployed"
fi

print_info "Creating ServiceMonitor for model: $MODEL_NAME"
print_info "  Namespace: $NAMESPACE"
print_info "  Runtime: $RUNTIME"
print_info "  Interval: $INTERVAL"
print_info "  Timeout: $TIMEOUT"
print_info "  Path: $PATH"

# Create ServiceMonitor
oc apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${MODEL_NAME}-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${RUNTIME}
    model: ${MODEL_NAME}
spec:
  endpoints:
    - interval: ${INTERVAL}
      port: ${PORT}
      path: ${PATH}
      scheme: http
      timeout: ${TIMEOUT}
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: ${MODEL_NAME}
EOF

if [ $? -eq 0 ]; then
    print_info "✓ ServiceMonitor created successfully"
    echo ""
    print_info "To verify ServiceMonitor:"
    echo "  oc get servicemonitor ${MODEL_NAME}-monitor -n ${NAMESPACE}"
    echo ""
    print_info "To check scrape targets in Prometheus:"
    echo "  oc get route -n openshift-user-workload-monitoring"
    echo "  Access Thanos Querier and check /targets page"
else
    print_error "Failed to create ServiceMonitor"
    exit 1
fi
