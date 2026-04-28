#!/bin/bash
# Hide or show restricted-access models in the LiteMaaS catalog.
#
# Restricted models (restricted_access=true) should be hidden from the
# "Available Models" browse page. Users who already have API keys can
# still call them — this only affects catalog discoverability.
#
# Usage:
#   ./scripts/hide-restricted-models.sh <namespace>           # hide (default)
#   ./scripts/hide-restricted-models.sh <namespace> hide      # hide restricted models
#   ./scripts/hide-restricted-models.sh <namespace> show      # show restricted models
#   ./scripts/hide-restricted-models.sh <namespace> status    # show current state
#
# Examples:
#   ./scripts/hide-restricted-models.sh litellm-rhpds
#   ./scripts/hide-restricted-models.sh litellm-rhpds status

set -e

NAMESPACE="${1:?Usage: $0 <namespace> [hide|show|status]}"
ACTION="${2:-hide}"

# Find the PostgreSQL pod
PG_POD=$(oc get pods -n "$NAMESPACE" -l app=litellm-postgres \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$PG_POD" ]]; then
  echo "ERROR: No PostgreSQL pod found in namespace '$NAMESPACE'"
  exit 1
fi

psql_exec() {
  oc exec "$PG_POD" -n "$NAMESPACE" -- psql -U litellm -d litellm -c "$1"
}

echo "Namespace : $NAMESPACE"
echo "Action    : $ACTION"
echo "Postgres  : $PG_POD"
echo ""

case "$ACTION" in

  status)
    echo "=== Current model catalog visibility ==="
    psql_exec "
      SELECT id,
             availability,
             CASE restricted_access WHEN true THEN 'yes' ELSE 'no' END AS restricted
      FROM models
      ORDER BY restricted_access DESC, id;
    "
    ;;

  hide)
    echo "=== Hiding restricted models from catalog ==="
    psql_exec "
      UPDATE models
      SET availability = 'unavailable'
      WHERE restricted_access = true
      RETURNING id;
    "
    echo ""
    echo "Done. These models are no longer visible in the Available Models catalog."
    echo "Users with existing API keys can still call them."
    ;;

  show)
    echo "=== Making restricted models visible in catalog ==="
    echo "WARNING: This will expose restricted models to all users browsing the catalog."
    echo "         They will still require admin approval to subscribe."
    read -r -p "Are you sure? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Aborted."
      exit 0
    fi
    psql_exec "
      UPDATE models
      SET availability = 'available'
      WHERE restricted_access = true
      RETURNING id;
    "
    echo ""
    echo "Done. Restricted models are now visible (but still require admin approval)."
    ;;

  *)
    echo "ERROR: Unknown action '$ACTION'. Use hide, show, or status."
    exit 1
    ;;

esac
