#!/bin/bash
# Create a virtual key for LiteMaaS users
#
# Usage: ./scripts/create-user-key.sh <namespace> <email> [models] [max_budget] [duration]

set -e

NAMESPACE="${1:?Usage: $0 <namespace> <email> [models] [max_budget] [duration]}"
USER_EMAIL="${2:?Usage: $0 <namespace> <email> [models] [max_budget] [duration]}"
MODELS="${3:-deepseek-chat}"
MAX_BUDGET="${4:-100}"
DURATION="${5:-30d}"

# Get LiteLLM master key
LITELLM_MASTER_KEY=$(oc get secret litellm-secret -n "$NAMESPACE" -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)

# Get LiteLLM URL
LITELLM_URL=$(oc get route litellm -n "$NAMESPACE" -o jsonpath='{.spec.host}')

echo "Creating virtual key for user: ${USER_EMAIL}"
echo "Namespace: ${NAMESPACE}"
echo "Models: ${MODELS}"
echo "Max Budget: \$${MAX_BUDGET}"
echo "Duration: ${DURATION}"
echo ""

# Create the virtual key
RESPONSE=$(curl -s "https://${LITELLM_URL}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"models\": [\"${MODELS}\"],
    \"max_budget\": ${MAX_BUDGET},
    \"duration\": \"${DURATION}\",
    \"metadata\": {
      \"user_email\": \"${USER_EMAIL}\",
      \"description\": \"User key for LiteMaaS\"
    }
  }")

echo "Response:"
echo "${RESPONSE}" | jq .

# Extract and display the key
KEY=$(echo "${RESPONSE}" | jq -r '.key')
echo ""
echo "========================================="
echo "Virtual Key Created!"
echo "========================================="
echo "Key: ${KEY}"
echo "User: ${USER_EMAIL}"
echo "Models: ${MODELS}"
echo "========================================="
echo ""
echo "Share this key with the user. They can use it to access models via:"
echo "  curl https://${LITELLM_URL}/chat/completions \\"
echo "    -H 'Authorization: Bearer ${KEY}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"${MODELS}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
echo ""
