# website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui - Complete Monitoring Stack

## 🚀 WSZYSTKIE BŁĘDY NAPRAWIONE!

### ✅ Naprawione w tej wersji:
1. **PostgreSQL** - Dodano securityContext (fsGroup/runAsUser) - naprawiony Permission denied
2. **Kafka** - Poprawiono image na bitnami/kafka:3.6.1 + dodano volumeClaimTemplates
3. **Kafka Exporter** - Zmieniono na danielqsj/kafka-exporter:v1.7.0
4. **Postgres Exporter** - Uproszczono konfigurację + dodano init container
5. **GitHub Actions** - Dodano password: ${{ secrets.GITHUB_TOKEN }}
6. **Vault** - Pełna konfiguracja StatefulSet
7. **Wszystkie wait-for init containers** - Używają pełnej nazwy DNS Kafki

## 🛠️ Quick Start

```bash
# Generate all files
./chatgpt.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Check all pods
kubectl get pods -n davtrowebdbvault -w

# Access applications:
# Main App: http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local
# Grafana: http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local (admin/admin)
# PgAdmin: http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local

# Initialize Vault (runs automatically)
kubectl wait --for=condition=complete job/vault-init -n davtrowebdbvault --timeout=120s
```

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | - |
| Grafana | http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin/admin |
| PgAdmin | http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local | - |

## 🔧 Integration Details:

1. **PostgreSQL** - Działa z poprawnym securityContext (999:999)
2. **Kafka** - KRaft mode z obrazem 3.6.1 + persistent storage
3. **Vault Integration** - Wszystkie sekrety w Vault
4. **Monitoring Stack** - Loki, Prometheus, Tempo połączone z Grafaną
5. **Kafka UI** - Poprawne połączenie z Kafką przez pełną nazwę DNS
6. **GitHub Actions** - Poprawna autentykacja do GHCR

## 📊 Monitoring Stack:

- **Prometheus** - metryki ze wszystkich serwisów
- **Grafana** - zunifikowane dashboardy
- **Loki** - centralizacja logów
- **Tempo** - distributed tracing
- **Postgres Exporter** - metryki bazy danych
- **Kafka Exporter** - metryki Kafki (danielqsj/kafka-exporter)
- **Node Exporter** - metryki systemowe

## 🔐 Security:

- Wszystkie hasła w Vault
- Network policies dla komunikacji
- Proper security contexts
- Health checks i resource limits

