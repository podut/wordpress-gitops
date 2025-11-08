# Stack GitOps Deployment

Acest depozit conține manifestele Kubernetes și scripturile folosite pentru a porni un stack format din Redis, MariaDB, phpMyAdmin și HashiCorp Vault, ce poate fi sincronizat ulterior de Argo CD.

## Pași rapizi
- Rulează scriptul de bootstrap (pornește Minikube și aplică Kustomize):
  ```bash
  scripts/bootstrap-minikube.sh
  ```
  Variabile utile pentru script:
  - `MINIKUBE_PROFILE`/`MINIKUBE_MEMORY`/`MINIKUBE_CPUS`/`MINIKUBE_DRIVER`
  - `KUSTOMIZE_PATH` (implicit `manifests`)
- Dacă preferi manual:
  ```bash
  minikube start --driver=docker
  kubectl apply -k manifests
  ```
- Actualizează `repoURL` din `manifests/argocd/application.yaml`, împinge repo-ul într-un remote vizibil de Argo CD și aplică aplicația (dacă nu ai făcut-o deja cu pasul precedent):
  ```bash
  kubectl apply -k manifests/argocd
  ```
  Argo CD va sincroniza folderul `manifests` (care include atât workload-urile, cât și aplicația).
- Populează secretele din Vault și rulează scriptul care le sincronizează în cluster:
  ```bash
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN="<token-ul tau>"
  scripts/sync-vault-secrets.sh
  ```
  Variabile utile (pot fi setate când rulezi scriptul):
  - `NAMESPACE` (implicit `stack-services`)
  - `MARIADB_PATH` (implicit `kv/stack/mariadb`)
  - `REDIS_PATH` (implicit `kv/stack/redis`)

## Structură
- `manifests/base` – conține `stack.yaml` și `kustomization.yaml` pentru workload-urile Redis/MariaDB/phpMyAdmin/Vault.
- `manifests/argocd` – conține aplicația Argo CD care urmărește acest repo.
- `manifests/kustomization.yaml` – combină baza și aplicația Argo CD pentru `kubectl apply -k manifests`.
- `scripts/bootstrap-minikube.sh` – pornește Minikube (driver Docker) și aplică manifestele.
- `scripts/sync-vault-secrets.sh` – sincronizează secretele din HashiCorp Vault către cluster.
