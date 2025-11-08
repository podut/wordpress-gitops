#!/usr/bin/env bash
set -euo pipefail

PROFILE=${MINIKUBE_PROFILE:-stack}
MEMORY=${MINIKUBE_MEMORY:-4096}
CPUS=${MINIKUBE_CPUS:-2}
DRIVER=${MINIKUBE_DRIVER:-docker}
KUSTOMIZE_PATH=${KUSTOMIZE_PATH:-manifests}

command -v minikube >/dev/null 2>&1 || { echo "minikube trebuie instalat inainte de a rula acest script" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl trebuie instalat inainte de a rula acest script" >&2; exit 1; }

printf "[1/3] Pornesc minikube (profil=%s, driver=%s, mem=%sMB, cpu=%s)\n" "$PROFILE" "$DRIVER" "$MEMORY" "$CPUS"
minikube start \
  --profile "$PROFILE" \
  --driver "$DRIVER" \
  --memory "$MEMORY" \
  --cpus "$CPUS"

printf "[2/3] Aștept ca nodurile să devină Ready...\n"
for _ in {1..24}; do
  if kubectl get nodes >/dev/null 2>&1; then
    if kubectl wait --for=condition=Ready nodes --all --timeout=10s >/dev/null 2>&1; then
      READY=1
      break
    fi
  fi
  sleep 5
done
if [[ -z "${READY:-}" ]]; then
  echo "Clusterul nu este gata după 2 minute. Verifică statusul minikube și reia comanda." >&2
  exit 1
fi

printf "[3/3] Aplic kustomization-ul din '%s'\n" "$KUSTOMIZE_PATH"
kubectl apply -k "$KUSTOMIZE_PATH"

cat <<MSG
---
Clusterul este pornit și manifestele au fost aplicate.
- Actualizează 'repoURL' din manifests/argocd/application.yaml înainte de a face push în repo-ul urmărit de Argo CD.
- Dacă rulezi Vault local, folosește scripts/sync-vault-secrets.sh după ce seturile KV sunt populate.
MSG
