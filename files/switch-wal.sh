#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?}"
NAMESPACE="${NAMESPACE:?}"

echo "[wal-switch] looking up primary pod for cluster $CLUSTER_NAME in $NAMESPACE"
POD="$(kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER_NAME,cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')"

if [ -z "$POD" ]; then
  echo "[wal-switch] ERROR: no primary pod found for cluster $CLUSTER_NAME" >&2
  exit 1
fi

echo "[wal-switch] switching WAL on $POD"
# Local peer auth over the unix socket (pg_ident maps the postgres OS user
# to the postgres role) - no password, no GRANT needed on any app role, and
# works the same whether enableSuperuserAccess is on or off. That flag only
# gates the *external*, password-based superuser Secret/Service - confirmed
# against a live cluster it has no bearing on local socket access from
# inside the pod, which is how CNPG's own instance manager operates too.
kubectl exec -n "$NAMESPACE" "$POD" -c postgres -- psql -U postgres -Atqc "SELECT pg_switch_wal();"
