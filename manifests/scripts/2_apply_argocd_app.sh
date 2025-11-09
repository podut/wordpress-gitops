#!/usr/bin/env bash
set -uo pipefail

# Minimal script: apply Argo CD Application into the cluster.
# Assumes Argo CD is already installed and running.

: "${ARGO_NS:=argocd}"
: "${APP_MANIFEST:=argocd/application.yaml}"
: "${APPLY_RETRY:=2}"
: "${APPLY_RETRY_DELAY:=3}"
: "${VERBOSE:=true}"
: "${LOG_DIR:=scripts}"
: "${LOG_FILE:=}"
: "${EXIT_ON_ERROR:=false}"

log() { printf "[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
err() { printf "[%s] [ERROR] %s\n" "$(date +'%H:%M:%S')" "$*" >&2; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Lipsește comanda '$1'"; exit 1; }; }
die_or_continue(){
  local msg="$1"; local code="${2:-1}"
  err "$msg"
  if [ "$EXIT_ON_ERROR" = "true" ]; then
    exit "$code"
  else
    FAILED=true
  fi
}

ensure_log_file() {
  [ -n "$LOG_FILE" ] || LOG_FILE="$LOG_DIR/argo_diag_$(date +%Y%m%d_%H%M%S).txt"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
}

run() {
  ensure_log_file
  printf "+ %s\n" "$*" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  return $rc
}
vrun() {
  if [ "${VERBOSE}" = "true" ]; then
    run "$@"
  else
    "$@"
  fi
}

diagnostics() {
  ensure_log_file
  log "Diagnostice rapide:" | tee -a "$LOG_FILE"
  run kubectl -n "$ARGO_NS" get pods || true
  run kubectl -n "$ARGO_NS" get events --sort-by=.lastTimestamp | tail -n 50 || true
}

main(){
  FAILED=false
  need_cmd kubectl || { err "kubectl nu este instalat în PATH"; return 0; }

  # Detect repo root relative to this script, to work from any CWD
  local script_dir repo_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"

  # Determine best apply target in priority:
  # 1) argocd/kustomization.yaml (apply -k)
  # 2) root kustomization.yaml (apply -k repo root)
  # 3) fallback to APP_MANIFEST (apply -f)
  APPLY_MODE="file"
  TARGET_PATH="$repo_root/$APP_MANIFEST"
  if [ -f "$repo_root/argocd/kustomization.yaml" ] || [ -f "$repo_root/argocd/kustomization.yml" ]; then
    APPLY_MODE="kustomize"
    TARGET_PATH="$repo_root/argocd"
  elif [ -f "$repo_root/kustomization.yaml" ] || [ -f "$repo_root/kustomization.yml" ]; then
    APPLY_MODE="kustomize"
    TARGET_PATH="$repo_root"
  elif [ ! -f "$TARGET_PATH" ]; then
    die_or_continue "Nu găsesc țintă de apply: nici argocd/kustomization, nici root kustomization, nici APP_MANIFEST ($APP_MANIFEST)." 2
  fi

  log "[1/3] Verific namespace '$ARGO_NS'" | tee -a "$LOG_FILE"
  if ! kubectl get ns "$ARGO_NS" >/dev/null 2>&1; then
    run kubectl create namespace "$ARGO_NS" || die_or_continue "Nu am putut crea namespace-ul '$ARGO_NS'" 4
  fi

  if [ "$APPLY_MODE" = "kustomize" ]; then
    log "[2/3] Aplic kustomization ('$TARGET_PATH') pentru resursele ArgoCD/Application."
  else
    log "[2/3] Aplic Application din fișier: $TARGET_PATH în namespace: $ARGO_NS"
  fi
  attempt=1
  while true; do
    set +e
    if [ "$APPLY_MODE" = "kustomize" ]; then
      vrun kubectl apply -n "$ARGO_NS" -k "$TARGET_PATH"
      rc=$?
    else
      vrun kubectl apply -n "$ARGO_NS" -f "$TARGET_PATH"
      rc=$?
    fi
    set -e
    if [ $rc -eq 0 ]; then
      break
    fi
    err "Eșec la apply (încercarea $attempt)."
    diagnostics
    if [ "$attempt" -ge "$APPLY_RETRY" ]; then
      die_or_continue "Apply a eșuat după $APPLY_RETRY încercări (rc=$rc)." "$rc"
      break
    fi
    log "Reîncerc peste ${APPLY_RETRY_DELAY}s..."
    sleep "$APPLY_RETRY_DELAY"
    attempt=$((attempt+1))
  done

  # Rezumat Applications
  log "[3/3] Applications în '$ARGO_NS':" | tee -a "$LOG_FILE"
  run kubectl -n "$ARGO_NS" get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status || true

  # Rezumat și hint-uri UI
  {
    echo ""
    echo "UI ArgoCD: https://localhost:8080 (dacă faci port-forward)"
    echo "Port-forward: kubectl -n $ARGO_NS port-forward svc/argocd-server 8080:443"
    echo "Parola inițială: kubectl -n $ARGO_NS get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  } | tee -a "$LOG_FILE"

  if [ "$FAILED" = true ]; then
    err "Script terminat cu erori (EXIT_ON_ERROR=false). Verifică $LOG_FILE pentru detalii."
  else
    log "Script terminat fără erori critice. Log: $LOG_FILE"
  fi
}

main "$@"
