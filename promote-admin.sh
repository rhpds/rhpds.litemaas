#!/bin/bash
# Promote a LiteMaaS user to admin role
#
# Usage: ./promote-admin.sh <namespace> <email>
#
# The user must have logged in via OAuth first.
# This script updates their role from {user} to {admin,user}.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ $# -ne 2 ]; then
    echo "Usage: $0 <namespace> <email>"
    echo ""
    echo "Examples:"
    echo "  $0 prod-rhdp psrivast@redhat.com"
    echo "  $0 litemaas ajammula@redhat.com"
    exit 1
fi

NAMESPACE="$1"
EMAIL="$2"

# Find postgres pod
POSTGRES_POD=$(oc get pods -n "$NAMESPACE" -l app=litellm-postgres -o name 2>/dev/null | head -1)
if [ -z "$POSTGRES_POD" ]; then
    echo -e "${RED}ERROR: No PostgreSQL pod found in namespace $NAMESPACE${NC}"
    exit 1
fi

# Check if user exists
USER_EXISTS=$(oc exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
    psql -U litellm -d litellm -t -c \
    "SELECT count(*) FROM users WHERE email = '$EMAIL';" 2>/dev/null | tr -d ' ')

if [ "$USER_EXISTS" = "0" ]; then
    echo -e "${RED}ERROR: User $EMAIL not found.${NC}"
    echo "The user must log in via OAuth first to create their account."
    echo ""
    echo "Current users:"
    oc exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U litellm -d litellm -c \
        "SELECT username, email, roles FROM users WHERE username != 'system';"
    exit 1
fi

# Promote to admin
oc exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
    psql -U litellm -d litellm -c \
    "UPDATE users SET roles = ARRAY['admin', 'user'] WHERE email = '$EMAIL';"

echo -e "${GREEN}Done.${NC} $EMAIL is now an admin in namespace $NAMESPACE."
echo ""

# Show result
oc exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
    psql -U litellm -d litellm -c \
    "SELECT username, email, roles FROM users WHERE email = '$EMAIL';"
