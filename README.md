# website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat - Unified GitOps Stack (Zintegrowane Kafka KRaft i Tracing)

🚀 **Kompleksowa aplikacja z pełnym stack'iem DevOps**

## 📋 Komponenty

### Aplikacja
- **FastAPI** - Strona osobista z ankietą. **Wysyła wiadomości do Kafka i Tracing do Tempo.**
- **PostgreSQL** - Baza danych
- **pgAdmin** - Zarządzanie bazą danych

### GitOps & Orchestracja
- **ArgoCD** - Continuous Deployment
- **Kustomize** - Zarządzanie konfiguracją
- **Kyverno** - Policy enforcement

### Bezpieczeństwo
- **Vault** - Zarządzanie sekretami

### Messaging & Cache
- **Kafka (KRaft)** - Kolejka wiadomości. **Uproszczona, bez ZooKeepera.** Aplikacja FastAPI jest Producentem.
- **Redis** - In-memory cache.

### Monitoring & Observability (Pełny Trójkąt)
- **Prometheus** - Metryki
- **Grafana** - Wizualizacja (Metryki, Logi, Ślady)
- **Loki** - Logi (Współpracuje z Promtail)
- **Tempo** - Distributed tracing. **Zbiera ślady OpenTelemetry z FastAPI.**
- **Promtail** - Agregacja logów

## 🚀 Użycie

### 1. Generowanie manifestów
```bash
chmod +x unified-deployment.sh
./unified-deployment.sh generate
```

### 2. Inicjalizacja i push do GitHub
```bash
git init
git add .
git commit -m "Initial commit - unified stack with Kafka KRaft and Tempo tracing"
git branch -M main
git remote add origin https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat.git
git push -u origin main
```

### 3. Weryfikacja lokalnie (opcjonalnie)
```bash
# Sprawdź czy Kustomize działa
kubectl kustomize manifests/base

# Sprawdź strukturę
tree manifests/
```

### 4. Deploy z ArgoCD
```bash
# Upewnij się że ArgoCD jest zainstalowany
kubectl get namespace argocd

# Zastosuj Application manifest
kubectl apply -f argocd-application.yaml

# Sprawdź status
kubectl get applications -n argocd
kubectl describe application website-db-stack -n argocd
```

## ⚠️ Typowe problemy

### Błąd: ImagePullBackOff lub CrashLoopBackOff w Kafka
**Przyczyna**: Zazwyczaj oznacza to, że kontener Kafka nie mógł się poprawnie uruchomić, ale błąd pobierania obrazu został naprawiony (używamy teraz stabilnego `bitnami/kafka:3.7.0`). Upewnij się, że PersistentVolumeClaim jest poprawnie powiązany.
**Rozwiązanie**: Sprawdź logi podu Kafka:
```bash
kubectl logs kafka-0 -n davtrowebdbvault
```
Pamiętaj, że w trybie KRaft wolumen musi zostać sformatowany tylko raz, co jest obsługiwane przez skrypt startowy kontenera.

### "app path does not exist"
**Przyczyna**: Manifesty nie zostały jeszcze wypushowane do repo lub ścieżka jest błędna.

**Rozwiązanie**:
1. Upewnij się że zrobiłeś `git push` po generowaniu
2. Sprawdź czy folder `manifests/base/` istnieje w repo na GitHub
3. Sprawdź czy plik `manifests/base/kustomization.yaml` jest dostępny

## 🌐 Dostęp

- **Aplikacja**: http://website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat.local
- **pgAdmin**: http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat.local (admin@admin.com / admin)
- **Grafana**: http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat.local (admin / admin)
- **Vault**: http://vault.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat.local:8200

## 📦 Namespace
`davtrowebdbvault`

## 🏗️ Architektura (Zintegrowana)

```
┌─────────────────────────────────────────────────────┐
│                    ArgoCD                           │
│              (Continuous Deployment)                │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│              Kubernetes Cluster                     │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐               │
│  │   FastAPI    │  │  PostgreSQL  │               │
│  │   Website    │──│   Database   │               │
│  └──────────────┘  └──────────────┘               │
│         │ Tracing (Tempo)                           │
│         ├────────────┬─────────────┬───────────────┤
│         ▼            ▼             ▼               ▼
│  ┌──────────┐  ┌──────────┐  ┌─────────┐    ┌──────────┐
│  │  Redis   │  │  Kafka   │  │  Vault  │    │ pgAdmin  │
│  └──────────┘  │ (KRaft)  │  └─────────┘    └──────────┘
│                  └──────────┘                                  │
│                  ^                                  │
│                  │ Wiadomości (Survey Topic)          │
│                  │                                  │
│  ┌─────────────────────────────────────────────┐  │
│  │         Observability Stack                 │  │
│  │  ┌──────────┐ ┌─────────┐ ┌──────────┐    │  │
│  │  │Prometheus│ │ Grafana │ │   Loki   │    │  │
│  │  └──────────┘ └─────────┘ └──────────┘    │  │
│  │  ┌──────────┐ ┌─────────┐                 │  │
│  │  │  Tempo   │ │Promtail │                 │  │
│  │  └──────────┘ └─────────┘                 │  │
│  └─────────────────────────────────────────────┘  │
│                                                     │
│  ┌─────────────────────────────────────────────┐  │
│  │              Kyverno Policies               │  │
│  │         (Policy Enforcement)                │  │
│  └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```
