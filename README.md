# webstack-gitops - Unified GitOps Stack (Finalna Wersja)

🚀 **Kompleksowa aplikacja z pełnym stack'iem DevOps**

## 📋 KOMPONENTY (WSZYSTKIE)
- **FastAPI** (App)
- **PostgreSQL** (DB)
- **pgAdmin** (DB UI)
- **Adminer** (DB UI Alternatywa)
- **Vault** (Secrets, z poprawionym initContainerem)
- **Kafka KRaft** (Messaging, bez Zookeepera)
- **Redis** (Cache)
- **Prometheus/Grafana/Loki/Tempo/Promtail** (Observability)
- **ArgoCD/Kyverno** (GitOps/Security)

## 🚀 FINALNE KROKI WDROŻENIA (KRYTYCZNE)

### 1. Generowanie i push do Git

Musisz wygenerować manifesty z **poprawionym Vaultem i Adminerem** i wypchnąć je do repozytorium.

```bash
# 1. Usuń stary folder, aby zresetować pliki
rm -rf manifests/ argocd-application.yaml

# 2. Uruchom skrypt
./unified-deployment.sh generate

# 3. Dodaj, commituj i push do repo (użyj nazwy webstack-gitops!)
git add .
git commit -m "Final Fix: Vault initContainer for read-only config fix and added Adminer component."
git push -u origin main
```

### 2. Czyszczenie starych zasobów w Kubernetes

**TO JEST KRYTYCZNE DLA NAPRAWY VAULT.** Musisz usunąć stary StatefulSet, aby ArgoCD mogło zastosować nową definicję z InitContainerem.

```bash
# USUŃ WSZYSTKIE StatefulSety, Deploymenty i Ingress, by wymusić restart z poprawną konfiguracją
kubectl delete deployment -l app -n davtrowebdbvault
kubectl delete statefulset -l app -n davtrowebdbvault
kubectl delete ingress webstack-gitops -n davtrowebdbvault

# USUŃ PVC (Ważne dla resetu Vault/Postgres/Kafka/Redis)
kubectl delete pvc -l app=vault -n davtrowebdbvault
kubectl delete pvc -l app=postgres -n davtrowebdbvault
kubectl delete pvc -l app=kafka -n davtrowebdbvault
kubectl delete pvc -l app=redis -n davtrowebdbvault

# Wymuś pełną synchronizację w ArgoCD
argocd app sync webstack-gitops --refresh --prune
```

### 3. Weryfikacja Podów i DNS

Po synchronizacji upewnij się, że wszystkie Pody są w stanie **Running**.

```bash
kubectl get pods -n davtrowebdbvault
```

**Upewnij się, że plik /etc/hosts zawiera nowe wpisy:**

```
# Zastąp XXX.XXX.XXX.XXX adresem IP Twojego Ingress Controller'a
XXX.XXX.XXX.XXX app.webstack-gitops.local
XXX.XXX.XXX.XXX pgadmin.webstack-gitops.local
XXX.XXX.XXX.XXX grafana.webstack-gitops.local
XXX.XXX.XXX.XXX adminer.webstack-gitops.local 
```

## 🌐 Dostęp
- **Aplikacja**: http://app.webstack-gitops.local
- **pgAdmin**: http://pgadmin.webstack-gitops.local (admin@admin.com / admin)
- **Adminer**: http://adminer.webstack-gitops.local (Server: `postgres`, User: `appuser`, Pass: `apppass`, DB: `appdb`)
- **Grafana**: http://grafana.webstack-gitops.local (admin / admin)
