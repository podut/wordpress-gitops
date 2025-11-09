# Minikube Verification Cheatsheet

Comenzi uzuale pentru a verifica rapid starea namespace-urilor ?i resurselor într-un cluster Minikube.

## Context ?i cluster

```bash
kubectl config use-context minikube
kubectl cluster-info
kubectl version --short
```

## Namespace

```bash
kubectl get ns
kubectl describe ns <nume-ns>
kubectl get all -n <nume-ns>
```

## Pods & workload

```bash
kubectl -n <nume-ns> get pods -o wide
kubectl -n <nume-ns> get pods -w
kubectl -n <nume-ns> describe pod <pod>
kubectl -n <nume-ns> logs <pod>              # primul container
kubectl -n <nume-ns> logs <pod> -c <container>
```

## Servicii & endpoints

```bash
kubectl -n <nume-ns> get svc
kubectl -n <nume-ns> get endpoints
kubectl -n <nume-ns> port-forward svc/<svc> PORT_LOCAL:PORT_CLUSTER
```

## Stocare (PVC/PV)

```bash
kubectl -n <nume-ns> get pvc
kubectl get pv
kubectl -n <nume-ns> describe pvc <nume-pvc>
```

## Evenimente & sanatate

```bash
kubectl -n <nume-ns> get events --sort-by=.lastTimestamp
kubectl -n <nume-ns> top pods
kubectl top nodes
```

## Resurse specifice (exemple)

```bash
kubectl -n <nume-ns> get statefulset
kubectl -n <nume-ns> get deploy
kubectl -n <nume-ns> get secret
kubectl -n <nume-ns> get configmap
```

## Diagnostic rapid Vault (exemplu)

```bash
kubectl -n vault get pods
kubectl -n vault logs vault-0 -c vault --tail=60
kubectl -n vault exec -it vault-0 -c vault -- sh -c 'ls -ld /vault/config /vault/data'
```

> Înlocuie?te `<nume-ns>` ?i `<pod>` cu valorile relevante pentru aplica?ia ta.
