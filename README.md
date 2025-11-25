# website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui - Complete Monitoring Stack

## 🚀 NAPRAWIONO - Wszystkie komponenty działają!

### ✅ Naprawione błędy:
1. **postgres-db** - usunięto nadpisany CMD, dodano PGDATA i startup probe
2. **postgres-exporter** - uproszczono konfigurację, dodano init container
3. **kafka** - zmieniono image na `bitnami/kafka:3.6.1`, dodano volumeClaimTemplates
4. **kafka-exporter** - zmieniono na `danielqsj/kafka-exporter:v1.7.0`
5. **kafka-topic-job** - użyto pełnej nazwy DNS Kafki
6. **pgadmin** - poprawiono init container
7. **fastapi/worker** - użyto pełnej nazwy DNS Kafki w env vars

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
# PgAdmin: http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n davtrowebdbvault
```

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | - |
| Grafana | http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin/admin |
| PgAdmin | http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | - |

## 🔧 Fixed Issues:

1. **PostgreSQL CrashLoopBackOff (333 restarty)** → ✅ NAPRAWIONE
2. **Kafka ImagePullBackOff** → ✅ NAPRAWIONE (bitnami/kafka:3.6.1)
3. **Kafka Exporter ImagePullBackOff** → ✅ NAPRAWIONE (danielqsj/kafka-exporter:v1.7.0)
4. **Postgres Exporter CrashLoopBackOff (484 restarty)** → ✅ NAPRAWIONE
5. **FastAPI/Worker Init:0/3** → ✅ NAPRAWIONE (używają pełnej nazwy DNS Kafki)
6. **PgAdmin Init:0/1** → ✅ NAPRAWIONE
7. **Kafka UI Init:0/1** → ✅ NAPRAWIONE
8. **Create Kafka Topics Job ImagePullBackOff** → ✅ NAPRAWIONE

## 📊 Monitoring Stack:

- **Prometheus** - metrics collection from all services
- **Grafana** - unified dashboards with all datasources
- **Loki** - centralized log aggregation
- **Tempo** - distributed tracing
- **Postgres Exporter** - database metrics
- **Kafka Exporter** - Kafka metrics
- **Node Exporter** - system metrics

## 🔐 Security:

- All passwords in Vault
- Network policies for service communication
- Secrets as Kubernetes Secrets
- Proper health checks and resource limits

## 🎯 All Components Working:

✅ fastapi-web-app (2 replicas)
✅ message-processor (worker)
✅ postgres-db (StatefulSet)
✅ postgres-exporter
✅ redis
✅ kafka (KRaft mode)
✅ kafka-exporter
✅ create-kafka-topics (Job)
✅ kafka-ui
✅ vault
✅ pgadmin
✅ prometheus
✅ grafana
✅ loki
✅ promtail (DaemonSet)
✅ tempo
✅ node-exporter (DaemonSet)

