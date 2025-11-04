# website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin - Unified GitOps Stack

🚀 **Kompleksowa aplikacja z pełnym stack'iem DevOps**

## 📋 Komponenty

### Aplikacja
- **FastAPI** - Strona osobista z ankietą
- **PostgreSQL** - Baza danych
- **pgAdmin** - Zarządzanie bazą danych

### GitOps & Orchestracja
- **ArgoCD** - Continuous Deployment
- **Kustomize** - Zarządzanie konfiguracją
- **Kyverno** - Policy enforcement

### Bezpieczeństwo
- **Vault** - Zarządzanie sekretami

### Messaging & Cache
- **Kafka + Zookeeper** - Kolejka wiadomości
- **Redis** - Cache i kolejki

### Monitoring & Observability
- **Prometheus** - Metryki
- **Grafana** - Wizualizacja
- **Loki** - Logi
- **Tempo** - Distributed tracing
- **Promtail** - Agregacja logów

## 🚀 Użycie

### 1. Generowanie manifestów
```bash
chmod +x unified-deployment.sh
./unified-deployment.sh generate
```

### 2. Inicjalizacja repozytorium
```bash
git init
git add .
git commit -m "Initial commit - unified stack"
git remote add origin https://github.com/exea-centrum/website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.git
git push -u origin main
```

### 3. Deploy z ArgoCD
```bash
kubectl apply -f manifests/base/argocd-app.yaml
```

## 🌐 Dostęp

- **Aplikacja**: http://website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.local
- **pgAdmin**: http://pgadmin.website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.local (admin@admin.com / admin)
- **Grafana**: http://grafana.website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.local (admin / admin)
- **Vault**: http://vault.website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.local:8200

## 📊 Baza danych

### Tabele:
- `survey_responses` - Odpowiedzi z ankiety
- `page_visits` - Statystyki odwiedzin
- `contact_messages` - Wiadomości kontaktowe

## 🔐 Sekretna konfiguracja

### GitHub Secrets wymagane:
- `GHCR_PAT` - Personal Access Token dla GitHub Container Registry

## 📦 Namespace
`davtrowebdb`

## 🏗️ Architektura

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
│         │                                           │
│         ├────────────┬─────────────┬───────────────┤
│         ▼            ▼             ▼               ▼
│  ┌──────────┐  ┌─────────┐  ┌─────────┐    ┌──────────┐
│  │  Redis   │  │  Kafka  │  │  Vault  │    │ pgAdmin  │
│  └──────────┘  └─────────┘  └─────────┘    └──────────┘
│                                                     │
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

## 🛠️ Rozwój

### Struktura projektu:
```
.
├── app/
│   ├── main.py              # FastAPI aplikacja
│   ├── requirements.txt     # Zależności Python
│   └── templates/
│       └── index.html       # Frontend
├── manifests/
│   └── base/               # Manifesty Kubernetes
│       ├── *.yaml
│       └── kustomization.yaml
├── .github/
│   └── workflows/
│       └── ci.yml          # GitHub Actions
├── Dockerfile
└── unified-deployment.sh   # Ten skrypt
```

## 📝 Licencja

MIT License - Dawid Trojanowski © 2025
