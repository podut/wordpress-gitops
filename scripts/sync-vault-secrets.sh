#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-stack-services}
MARIADB_PATH=${MARIADB_PATH:-kv/stack/mariadb}
REDIS_PATH=${REDIS_PATH:-kv/stack/redis}

command -v vault >/dev/null 2>&1 || { echo "vault CLI is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

kv_get() {
  local path="$1"
  vault kv get -format=json "$path" | jq -r '.data.data'
}

mariadb_json=$(kv_get "$MARIADB_PATH")
redis_json=$(kv_get "$REDIS_PATH")

kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: stack-db-credentials
  labels:
    app.kubernetes.io/part-of: stack
stringData:
  MARIADB_ROOT_PASSWORD: $(echo "$mariadb_json" | jq -r '.root_password')
  MARIADB_DATABASE: $(echo "$mariadb_json" | jq -r '.database')
  MARIADB_USER: $(echo "$mariadb_json" | jq -r '.username')
  MARIADB_PASSWORD: $(echo "$mariadb_json" | jq -r '.password')
YAML

kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: redis-auth
  labels:
    app.kubernetes.io/part-of: stack
stringData:
  REDIS_PASSWORD: $(echo "$redis_json" | jq -r '.password')
YAML
