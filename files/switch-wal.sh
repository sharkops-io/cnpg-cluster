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
#
# pg_switch_wal() alone is a documented no-op when there's been zero WAL
# activity since the last switch - exactly the idle-database case this job
# exists to fix. Confirmed live against a genuinely idle cluster: LSN didn't
# move at all from a bare pg_switch_wal() call. pg_logical_emit_message()
# writes a real, tiny WAL record without touching any table, giving the
# switch something to actually close - confirmed this combination advances
# to a new segment and gets archived within seconds, even on an otherwise
# completely idle database.
kubectl exec -n "$NAMESPACE" "$POD" -c postgres -- psql -U postgres -Atqc "
SELECT pg_logical_emit_message(false, 'wal-switch-heartbeat', now()::text);
SELECT pg_switch_wal();
"
