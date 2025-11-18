# website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui - Complete Monitoring Stack

## 🚀 Now with Consistent Labels and All Components Restored!

### ✅ Fixed Issues:
- **Spójne etykiety** - wszystkie komponenty używają tej samej konwencji
- **Przywrócone komponenty** - wszystkie usunięte komponenty przywrócone
- **Consistent selectors** - wszystkie Service i Deployment używają tych samych selektorów
- **Fixed network policies** - poprawiona komunikacja między komponentami

### 🏷️ Label Convention:
```
app: website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
component: <service-name>
app.kubernetes.io/name: website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
app.kubernetes.io/instance: website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
app.kubernetes.io/component: <service-name>
```

## 🛠️ Quick Start

```bash
# Generate all files
./chatgpt.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Check all pods
kubectl get pods -n davtrowebdbvault

# Access applications:
# Main App: http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local
# Grafana: http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local (admin/admin)

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n davtrowebdbvault
```

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | - |
| Grafana | http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin/admin |
| PgAdmin | http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui.davtrowebdbvault.svc.cluster.local:8080 | - |

## 🔧 Key Fixes Applied:

1. **PostgreSQL** - dodano `listen_addresses=*` i poprawiono init containers
2. **Consistent Labels** - wszystkie zasoby używają spójnych etykiet
3. **Network Policies** - poprawiona komunikacja między wszystkimi komponentami
4. **Health Checks** - dodano poprawne health checks dla wszystkich usług
5. **Resource Limits** - ustawione sensowne limity zasobów
6. **All Components Restored** - przywrócono wszystkie usunięte komponenty

## 📊 Monitoring Stack:

- **Prometheus** - metrics collection
- **Grafana** - dashboards and visualization  
- **Loki** - log aggregation
- **Tempo** - distributed tracing
- **Postgres Exporter** - database metrics
- **Kafka Exporter** - Kafka metrics
- **Node Exporter** - system metrics

## 🚀 Features

- **FastAPI** web application with survey system
- **Redis** for message queue
- **Kafka** for event streaming
- **PostgreSQL** for data persistence
- **Vault** for secrets management
- **Full monitoring** with Prometheus/Grafana/Loki/Tempo
- **Network policies** for security
- **Health checks** and readiness probes

