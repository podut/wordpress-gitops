#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Minikube + Argo CD and apply GitOps manifests with layered checks

: "${ARGO_NS:=argocd}"
: "${ARGO_MANIFEST_URL:=https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
: "${KUSTOMIZE_PATH:=.}"
# Minikube topology defaults
: "${MINIKUBE_DRIVER:=docker}"
: "${MINIKUBE_NODES:=2}"
# Ready check knobs
: "${READY_CHECK_INTERVAL:=5}"
: "${READY_MAX_ATTEMPTS:=1800}"
# Apply retry knobs
: "${APPLY_RETRY:=3}"
: "${APPLY_RETRY_DELAY:=5}"
: "${VERBOSE:=true}"

log() { printf "[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
err() { printf "[%s] [ERROR] %s\n" "$(date +'%H:%M:%S')" "$*" >&2; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Lipsește comanda '$1'"; exit 1; }; }

run() {
  printf "+ %s\n" "$*"
  "$@"
}
vrun() {
  if [ "${VERBOSE}" = "true" ]; then
    run "$@"
  else
    "$@"
  fi
}

wait_for_pods_ready() {
  local ns="$1"
  local interval="${READY_CHECK_INTERVAL}"
  local attempts=0
  log "Aștept pod-urile să fie Ready în namespace '$ns' (interval ${interval}s)..."
  while true; do
    if vrun kubectl get pods -n "$ns" >/dev/null 2>&1; then
      local pod_count
      pod_count=$(vrun kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [ "${pod_count:-0}" -gt 0 ]; then
        local not_ready
        not_ready=$(vrun kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $3}' | grep -vE 'Running|Completed|Succeeded' || true)
        if [ -z "$not_ready" ]; then
          log "Pod-urile sunt gata în '$ns'."
          break
        fi
      fi
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$READY_MAX_ATTEMPTS" ]; then
      err "Prea multe încercări așteptând pod-urile în '$ns'."
      vrun kubectl get pods -n "$ns" || true
      exit 1
    fi
    sleep "$interval"
  done
}

wait_for_deployments_available() {
  local ns="$1"
  local interval="${READY_CHECK_INTERVAL}"
  local attempts=0
  if ! vrun kubectl get deploy -n "$ns" >/dev/null 2>&1; then
    return 0
  fi
  log "Aștept deployments Available în namespace '$ns' (interval ${interval}s)..."
  while true; do
    local pending
    if command -v jq >/dev/null 2>&1; then
      pending=$(vrun kubectl get deploy -n "$ns" -o json 2>/dev/null | jq -r \
        '.items[] | select(.status.conditions[]? | select(.type=="Available" and .status!="True")) | .metadata.name' 2>/dev/null || true)
    else
      pending=$(vrun kubectl get deploy -n "$ns" --no-headers 2>/dev/null | awk '$5!=$6 {print $1}')
    fi
    if [ -z "$pending" ]; then
      log "Deployments Available în '$ns'."
      break
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$READY_MAX_ATTEMPTS" ]; then
      err "Prea multe încercări așteptând deployments Available în '$ns'."
      vrun kubectl get deploy -n "$ns"
      return 1
    fi
    sleep "$interval"
  done
}

ensure_namespace() {
  local ns="$1"
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    log "Creez namespace '$ns'..."
    run kubectl create namespace "$ns"
  else
    log "Namespace '$ns' există."
  fi
}

install_or_update_argocd() {
  if ! kubectl get deploy -n "$ARGO_NS" argocd-server >/dev/null 2>&1; then
    log "Instalez Argo CD (manifest oficial)..."
    run kubectl apply -n "$ARGO_NS" -f "$ARGO_MANIFEST_URL"
  else
    log "Argo CD detectat. Aplic actualizări din manifestul oficial (idempotent)..."
    run kubectl apply -n "$ARGO_NS" -f "$ARGO_MANIFEST_URL" || log "Skip update (posibil fără schimbări)."
  fi
}

apply_with_retry() {
  local target="$1"
  local attempt=1
  while true; do
      if run kubectl apply -k "$target"; then
        log "Apply reușit pentru '$target'."
        break
      fi
    if [ "$attempt" -ge "$APPLY_RETRY" ]; then
      err "Apply a eșuat după $APPLY_RETRY încercări pentru '$target'."
      exit 1
    fi
    log "Apply a eșuat (încercarea $attempt) pentru '$target'. Reîncerc peste ${APPLY_RETRY_DELAY}s..."
    sleep "$APPLY_RETRY_DELAY"
    attempt=$((attempt+1))
  done
}

apply_gitops_manifests() {
  local root="${1:-.}"
  if [ -f "$root/kustomization.yaml" ] || [ -f "$root/kustomization.yml" ]; then
    log "Aplic kustomize din '$root' (va referi alte kustomization-uri/stack-uri)..."
    apply_with_retry "$root"
  else
    err "Nu am găsit un kustomization.yaml în '$root'. Setează KUSTOMIZE_PATH corect."
    exit 1
  fi
}

port_forward_argocd() {
  if command -v nohup >/dev/null 2>&1; then
    if ! (echo > /dev/tcp/127.0.0.1/8080) >/dev/null 2>&1; then
      log "Pornesc port-forward pentru Argo CD UI la https://localhost:8080 ..."
      printf "+ %s\n" "kubectl -n $ARGO_NS port-forward svc/argocd-server 8080:443 &"; nohup kubectl -n "$ARGO_NS" port-forward svc/argocd-server 8080:443 >/dev/null 2>&1 &
      log "User: admin | Parola inițială: kubectl -n $ARGO_NS get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    else
      log "Port 8080 ocupat; sar peste port-forward."
    fi
  fi
}

main() {
  need_cmd kubectl
  need_cmd minikube

  # 1) Ensure a Kubernetes cluster (prefer Minikube)
  if ! kubectl cluster-info >/dev/null 2>&1; then
    log "Nu există cluster activ. Pornesc Minikube (--driver=${MINIKUBE_DRIVER} --nodes=${MINIKUBE_NODES})..."
    run minikube start --driver="${MINIKUBE_DRIVER}" --nodes="${MINIKUBE_NODES}" --embed-certs
  else
    if vrun kubectl config get-contexts minikube >/dev/null 2>&1; then
      log "Setez contextul 'minikube'..."
      run kubectl config use-context minikube >/dev/null
    else
      log "Folosesc contextul Kubernetes curent."
    fi
  fi

  # 2) Ensure ArgoCD namespace and install/update ArgoCD
  ensure_namespace "$ARGO_NS"
  install_or_update_argocd

  # 3) Wait until ArgoCD is fully ready
  wait_for_pods_ready "$ARGO_NS"
  wait_for_deployments_available "$ARGO_NS" || true

  # 4) Apply your GitOps kustomize în ordine: argocd -> rest (ex. base)
  apply_gitops_manifests "$KUSTOMIZE_PATH"

  # 5) Optional: port-forward for convenience
  port_forward_argocd || true

  log "Bootstrap finalizat."
}

main "$@"
