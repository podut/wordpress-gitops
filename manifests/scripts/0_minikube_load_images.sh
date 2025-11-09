#!/usr/bin/env bash
set -euo pipefail

# Detect container images from kustomize/manifests and load existing local images into Minikube.
# - Reads from KUSTOMIZE_PATH (default: manifests/base)
# - Optionally ensures Minikube is running with desired topology before loading images.

: "${KUSTOMIZE_PATH:=manifests/base}"
# Control cluster ensure behavior
: "${ENSURE_MINIKUBE:=true}"
: "${MINIKUBE_DRIVER:=docker}"
: "${MINIKUBE_NODES:=2}"

log() { printf "[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
err() { printf "[%s] [ERROR] %s\n" "$(date +'%H:%M:%S')" "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Lipsește comanda '$1'"; exit 1; }
}

render_manifests() {
  # Prefer kubectl kustomize or kustomize build if available
  if [ -f "$KUSTOMIZE_PATH/kustomization.yaml" ] || [ -f "$KUSTOMIZE_PATH/kustomization.yml" ]; then
    if command -v kubectl >/dev/null 2>&1 && kubectl kustomize -h >/dev/null 2>&1; then
      kubectl kustomize "$KUSTOMIZE_PATH"
      return 0
    fi
    if command -v kustomize >/dev/null 2>&1; then
      kustomize build "$KUSTOMIZE_PATH"
      return 0
    fi
  fi
  # Fallback: cat all yaml/yml files
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-heading "" "$KUSTOMIZE_PATH" -g "*.y?ml" -S -U 2>/dev/null | sed 's/^.*://'
  else
    find "$KUSTOMIZE_PATH" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec cat {} +
  fi
}

extract_images() {
  # Try yq if present for robust parsing
  if command -v yq >/dev/null 2>&1; then
    yq -r '..|.image? // empty' <<<"$1" | awk 'NF' | sort -u
    return 0
  fi
  # Fallback: grep image: lines and split
  printf "%s" "$1" | grep -E 'image:\s*' | sed -E 's/.*image:\s*"?([^"\s]+)"?.*/\1/' | awk 'NF' | sort -u
}

main() {
  need_cmd minikube

  # Optionally ensure minikube up with given driver/nodes
  if [ "${ENSURE_MINIKUBE}" = "true" ]; then
    if ! kubectl cluster-info >/dev/null 2>&1; then
      log "Pornesc Minikube: --driver=${MINIKUBE_DRIVER} --nodes=${MINIKUBE_NODES} ..."
      minikube start --driver="${MINIKUBE_DRIVER}" --nodes="${MINIKUBE_NODES}" --embed-certs
    else
      # Prefer switching to minikube if context exists
      if kubectl config get-contexts minikube >/dev/null 2>&1; then
        log "Setez contextul 'minikube' existent."
        kubectl config use-context minikube >/dev/null
      else
        log "Cluster activ detectat; continui cu contextul curent."
      fi
    fi
  fi

  images_manifest=$(render_manifests || true)
  if [ -z "${images_manifest:-}" ]; then
    err "Nu am putut renderiza manifeste din '$KUSTOMIZE_PATH'. Verifică calea."
    exit 1
  fi
  images=$(extract_images "$images_manifest" || true)
  if [ -z "${images:-}" ]; then
    log "Nu am găsit imagini în manifeste. Nimic de încărcat."
    exit 0
  fi

  log "Imagini detectate:"; printf "%s\n" "$images"

  loaded=0; skipped=0
  while IFS= read -r img; do
    [ -z "$img" ] && continue
    if command -v docker >/dev/null 2>&1 && docker image inspect "$img" >/dev/null 2>&1; then
      log "Încărcare în Minikube: $img"
      minikube image load "$img"
      loaded=$((loaded+1))
      continue
    fi
    if command -v nerdctl >/dev/null 2>&1 && nerdctl image inspect "$img" >/dev/null 2>&1; then
      log "Încărcare în Minikube (nerdctl): $img"
      minikube image load "$img"
      loaded=$((loaded+1))
      continue
    fi
    log "Sarit (imagine lipsă local): $img"
    skipped=$((skipped+1))
  done <<< "$images"

  log "Finalizat. Încărcate: $loaded | Sărite: $skipped"
}

main "$@"

