#!/bin/bash
# =============================================================================
# Add Grafana Admin User
# =============================================================================
# Adds a user to the Grafana admin RoleBinding
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
Usage: $0 <username> <namespace> [options]

Add a user to the Grafana admin RoleBinding.

Arguments:
  username                OpenShift username (e.g., psrivast, not psrivast@redhat.com)
  namespace               Namespace where Grafana is deployed

Options:
  --rolebinding NAME      RoleBinding name (default: grafana-admin)
  --role ROLE             ClusterRole to bind (default: admin)
  -h, --help              Show this help message

Examples:
  # Add user to Grafana admins
  $0 psrivast llm-hosting

  # Add user with custom role
  $0 viewer llm-hosting --role view

  # Use custom RoleBinding name
  $0 admin llm-hosting --rolebinding custom-grafana-admin

Note: Use OpenShift username, not email address.
      Check your username with: oc whoami
EOF
}

# Default values
ROLEBINDING="grafana-admin"
ROLE="admin"

# Parse arguments
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

USERNAME="$1"
NAMESPACE="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case $1 in
        --rolebinding)
            ROLEBINDING="$2"
            shift 2
            ;;
        --role)
            ROLE="$2"
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

# Validate username format (alphanumeric, underscore, hyphen, dot)
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    print_error "Invalid username format: $USERNAME"
    print_error "Username should contain only letters, numbers, dots, hyphens, or underscores"
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

print_info "Adding user to Grafana admins"
print_info "  User: $USERNAME"
print_info "  Namespace: $NAMESPACE"
print_info "  RoleBinding: $ROLEBINDING"
print_info "  Role: $ROLE"

# Check if RoleBinding exists
if oc get rolebinding "$ROLEBINDING" -n "$NAMESPACE" &> /dev/null; then
    print_info "RoleBinding $ROLEBINDING exists, checking for user..."

    # Check if user already exists
    if oc get rolebinding "$ROLEBINDING" -n "$NAMESPACE" -o yaml | grep -q "name: $USERNAME"; then
        print_warn "User $USERNAME is already in RoleBinding $ROLEBINDING"
        exit 0
    fi

    # Add user to existing RoleBinding
    print_info "Adding user to existing RoleBinding..."

    oc patch rolebinding "$ROLEBINDING" -n "$NAMESPACE" --type=json -p="[
      {
        \"op\": \"add\",
        \"path\": \"/subjects/-\",
        \"value\": {
          \"apiGroup\": \"rbac.authorization.k8s.io\",
          \"kind\": \"User\",
          \"name\": \"$USERNAME\"
        }
      }
    ]"
else
    print_info "RoleBinding $ROLEBINDING does not exist, creating..."

    # Create new RoleBinding
    oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLEBINDING}
  namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${ROLE}
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: ${USERNAME}
EOF
fi

if [ $? -eq 0 ]; then
    print_info "✓ User added to RoleBinding successfully"

    # Create GrafanaUser resource for admin access within Grafana
    print_info "Creating GrafanaUser resource for Grafana Admin access..."

    oc apply -f - <<EOF
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaUser
metadata:
  name: grafana-user-${USERNAME}
  namespace: ${NAMESPACE}
spec:
  user:
    login: ${USERNAME}
    email: ${USERNAME}@redhat.com
    name: ${USERNAME}
    role: Admin
  instanceSelector:
    matchLabels:
      dashboards: grafana
EOF

    if [ $? -eq 0 ]; then
        print_info "✓ GrafanaUser created successfully"
    else
        print_warn "Failed to create GrafanaUser (user may still have access via OAuth)"
    fi

    echo ""
    print_info "To verify RoleBinding:"
    echo "  oc get rolebinding ${ROLEBINDING} -n ${NAMESPACE} -o yaml"
    echo ""
    print_info "To verify GrafanaUser:"
    echo "  oc get grafanauser grafana-user-${USERNAME} -n ${NAMESPACE}"
    echo ""
    print_info "To list all admin users:"
    echo "  oc get rolebinding ${ROLEBINDING} -n ${NAMESPACE} -o jsonpath='{.subjects[*].name}'"
    echo ""
    print_info "User can now access Grafana at:"
    GRAFANA_URL=$(oc get route grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not found")
    if [ "$GRAFANA_URL" != "Not found" ]; then
        echo "  https://${GRAFANA_URL}"
    else
        echo "  (Route not found - check: oc get route -n ${NAMESPACE})"
    fi
else
    print_error "Failed to add user to RoleBinding"
    exit 1
fi
