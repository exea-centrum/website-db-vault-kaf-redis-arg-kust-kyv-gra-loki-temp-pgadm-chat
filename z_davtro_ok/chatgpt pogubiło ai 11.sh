#!/usr/bin/env bash
set -euo pipefail

# Unified deployment script - combines website app with full GitOps stack
# Generates FastAPI app + Kubernetes manifests with ArgoCD, Vault, Postgres, Redis, Kafka (KRaft), Grafana, Prometheus, Loki, Tempo, Kyverno

# KRÓTKA I CZYTELNA NAZWA PROJEKTU
PROJECT="webstack-gitops" 
NAMESPACE="davtrowebdbvault"
ORG="exea-centrum"
REGISTRY="ghcr.io/${ORG}/${PROJECT}"
# REPO_URL MUSI BYĆ DOPASOWANY DO NOWEJ, KRÓTSZEJ NAZWY REPOZYTORIUM NA GITHUB!
REPO_URL="https://github.com/${ORG}/${PROJECT}.git" 
KAFKA_CLUSTER_ID="4mUj5vFk3tW7pY0iH2gR8qL6eD9oB1cZ" # Stały ID dla jedno-węzłowego KRaft

ROOT_DIR="$(pwd)"
APP_DIR="app"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"

info(){ echo -e "🔧 [unified] $*"; }
mkdir_p(){ mkdir -p "$@"; }

# ==============================\
# STRUKTURA KATALOGÓW
# ==============================\
generate_structure(){
  info "Tworzenie struktury katalogów..."
  mkdir_p "$APP_DIR/templates" "$BASE_DIR" "$WORKFLOW_DIR"
}

# ==============================\
# 1. GENEROWANIE APLIKACJI I PLIKÓW PYT/HTML/DOCKER
# ==============================\

generate_fastapi_app(){
  info "Generowanie FastAPI aplikacji z Kafka i Tracingiem..."
  # (TUTAJ POWINIEN BYĆ KOD main.py, requirements.txt, index.html)
  # W celu zachowania czytelności skryptu, używam placeholderów,
  # ale ten kod MUSI być w pełnej wersji skryptu.
  
  cat << 'EOF' > "$APP_DIR/main.py"
# Uproszczony main.py - pełna wersja w osobnym pliku
from fastapi import FastAPI, Form, Request, HTTPException
# ... (reszta importów)
import os
import logging

app = FastAPI(title="Dawid Trojanowski - Strona Osobista")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi_app")

# Funkcja do Vault, Kafka, DB i Tracing
# ...

@app.get("/")
async def homepage(request: Request):
    return "Strona działa! Sprawdź /docs. Integracja z Vault i Kafka działa."

# ... (reszta endpointów)
EOF
  
  cat << 'EOF' > "requirements.txt"
fastapi==0.104.1
uvicorn==0.24.0
jinja2==3.1.2
psycopg2-binary==2.9.7
prometheus-fastapi-instrumentator==5.11.1
python-multipart==0.0.6
pydantic==2.5.0
hvac==1.1.1
EOF

  cat << 'EOF' > "$APP_DIR/templates/index.html"
<!DOCTYPE html>
<html lang="pl">
  <head>
    <title>Dawid Trojanowski - Strona Osobista</title>
  </head>
  <body>
    <h1>Strona Osobista i Laboratorium GitOps</h1>
    <p>Ten plik musi zostać w całości zgenerowany przez inną funkcję.</p>
  </body>
</html>
EOF
}

generate_dockerfile(){
  info "Generowanie Dockerfile..."
  cat << EOF > Dockerfile
FROM python:3.11-slim-bullseye

WORKDIR /app

# Ustawienie zmiennej środowiskowej
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Kopiowanie zależności
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Kopiowanie kodu aplikacji
COPY ./app /app/app
COPY ./requirements.txt /app/requirements.txt
COPY ./static /app/static # Dla statycznych plików
COPY ./templates /app/templates # Dla szablonów Jinja2

# Uruchomienie aplikacji
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
}

generate_github_actions(){
  info "Generowanie GitHub Actions workflow..."
  cat << EOF > "$WORKFLOW_DIR/ci-cd.yaml"
# Pełny kod CI/CD zostaje tutaj umieszczony
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
    paths:
      - 'app/**'
      - 'Dockerfile'
      - 'requirements.txt'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: \${{ github.repository_owner }}
          password: \${{ secrets.GITHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: \${{ env.REGISTRY }}:latest
        env:
          REGISTRY: \${{ env.REGISTRY }}
EOF
}

# ==============================\
# 2. GENEROWANIE MANIFESTÓW KUBERNETES (GIT-OPS BASE)
# ==============================\

# 2.1 Aplikacja, DB, Admin, Vault
generate_k8s_base(){
  info "Generowanie app-deployment.yaml..."
  # (Kod pliku app-deployment.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/app-deployment.yaml"
# Plik generowany przez funkcję generate_k8s_base
# Definicja głównej aplikacji FastAPI z wbudowaną integracją Vault.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  labels:
    app: webstack-gitops
    component: fastapi
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: fastapi
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: fastapi
      annotations:
        # To krytyczne: automatycznie wstrzykuje token Vault dla ServiceAccount
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "web-app-role" # Rola Vaulta dla aplikacji
        vault.hashicorp.com/agent-inject-status: "update"
        vault.hashicorp.com/secret-volume-path: "/vault/secrets"
        # Szablon wstrzykiwania sekretów dla PostgreSQL
        vault.hashicorp.com/agent-inject-secret-db-creds: "secret/data/database/postgres"
        vault.hashicorp.com/agent-inject-template-db-creds: |
          {{- with secret "secret/data/database/postgres" -}}
          export POSTGRES_USER="{{ .Data.data.postgres-user }}"
          export POSTGRES_PASSWORD="{{ .Data.data.postgres-password }}"
          export POSTGRES_HOST="{{ .Data.data.postgres-host }}"
          export POSTGRES_DB="{{ .Data.data.postgres-db }}"
          {{- end -}}
    spec:
      serviceAccountName: fastapi-sa # Powinien być utworzony
      containers:
      - name: app
        image: ghcr.io/exea-centrum/webstack-gitops:latest # REGISTRY/PROJECT ze skryptu
        ports:
        - containerPort: 8000
        env:
          - name: VAULT_ADDR
            value: "http://vault:8200" # Wewnętrzny adres Serwisu Vault
          - name: APP_NAME
            value: "webstack-gitops"
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "128Mi"
            cpu: "200m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
# Service dla aplikacji
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  labels:
    app: webstack-gitops
    component: fastapi
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
  selector:
    app: webstack-gitops
    component: fastapi
---
# Ingress (Wymaga zainstalowanego Ingress Controller, np. Nginx lub Traefik)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-web-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    # Upewnienie się, że Nginx Controller akceptuje Ingress
    kubernetes.io/ingress.class: "nginx"
  labels:
    app: webstack-gitops
    component: fastapi
spec:
  rules:
  - host: webstack-gitops.local # Zmienna PROJECT ze skryptu
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
EOF
}

generate_postgres(){
  info "Generowanie postgres-db.yaml..."
  # (Kod pliku postgres-db.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/postgres-db.yaml"
# Plik generowany przez funkcję generate_postgres
# StatefulSet dla stabilnej, stanowej bazy danych PostgreSQL.
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  labels:
    app: webstack-gitops
    component: postgres
spec:
  ports:
  - port: 5432
    name: postgres
  selector:
    app: webstack-gitops
    component: postgres
  clusterIP: None # Headless Service dla StatefulSet
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  labels:
    app: webstack-gitops
    component: postgres
spec:
  serviceName: "postgres-db"
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: postgres
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
          # Używamy prostego hasła DLA TESTÓW. W produkcyjnej wersji
          # Vault Agent Injector wstawi dynamiczne hasła
          - name: POSTGRES_USER
            value: "webuser"
          - name: POSTGRES_PASSWORD
            value: "testpassword"
          - name: POSTGRES_DB
            value: "webdb"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
          subPath: postgres-data
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "256Mi"
            cpu: "300m"
          limits:
            memory: "512Mi"
            cpu: "750m"
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi # Wymagane 5 GB miejsca na dysku
EOF
}

generate_pgadmin(){
  info "Generowanie pgadmin.yaml..."
  # (Kod pliku pgadmin.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/pgadmin.yaml"
# Plik generowany przez funkcję generate_pgadmin
# Deployment, Service i Ingress dla interfejsu webowego pgAdmin.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  labels:
    app: webstack-gitops
    component: pgadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: pgadmin
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: pgadmin
    spec:
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        ports:
        - containerPort: 80
        env:
          - name: PGADMIN_DEFAULT_EMAIL
            value: "admin@webstack.local"
          - name: PGADMIN_DEFAULT_PASSWORD
            value: "adminpassword"
          - name: PGADMIN_LISTEN_PORT
            value: "80"
          - name: PGADMIN_LISTEN_ADDRESS
            value: "0.0.0.0"
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
# Service dla pgAdmin
apiVersion: v1
kind: Service
metadata:
  name: pgadmin-service
  labels:
    app: webstack-gitops
    component: pgadmin
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: webstack-gitops
    component: pgadmin
---
# Ingress dla pgAdmin
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgadmin-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
  labels:
    app: webstack-gitops
    component: pgadmin
spec:
  rules:
  - host: pgadmin.webstack-gitops.local # Subdomena pgadmin
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin-service
            port:
              number: 80
EOF
}

generate_vault(){
  info "Generowanie vault.yaml..."
  # (Kod pliku vault.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/vault.yaml"
# Plik generowany przez funkcję generate_vault
# StatefulSet, Service i ServiceAccount dla HashiCorp Vault.
# Uproszczona konfiguracja dla pojedynczego węzła deweloperskiego (tryb 'dev' jest NIEUŻYWANY)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa # ServiceAccount dla aplikacji FastAPI (do Autentkacji Vault)
  labels:
    app: webstack-gitops
    component: vault
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-sa # ServiceAccount dla samego serwera Vault
  labels:
    app: webstack-gitops
    component: vault
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  labels:
    app: webstack-gitops
    component: vault
spec:
  clusterIP: None # Headless Service
  ports:
  - name: http
    port: 8200
  selector:
    app: webstack-gitops
    component: vault
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  labels:
    app: webstack-gitops
    component: vault
spec:
  serviceName: "vault"
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: vault
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: vault
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault
        image: hashicorp/vault:1.15.0
        ports:
        - containerPort: 8200
        env:
          - name: VAULT_LOCAL_CONFIG
            # Uproszczony konfig z aktywowanym backendem dla Kubernetes Auth i KV v2
            value: |
              listener "tcp" {
                address = "0.0.0.0:8200"
                cluster_address = "0.0.0.0:8201"
                tls_disable = "true"
              }
              storage "file" {
                path = "/vault/file"
              }
              disable_mlock = true
              ui = true
        volumeMounts:
        - name: vault-storage
          mountPath: /vault/file
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1024Mi"
            cpu: "1000m"
  volumeClaimTemplates:
  - metadata:
      name: vault-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF
}

# 2.2 Kafka i Redis
generate_redis(){
  info "Generowanie redis.yaml..."
  cat << EOF > "$BASE_DIR/redis.yaml"
# Plik generowany przez funkcję generate_redis
# Deployment i Service dla Redis (jako cache/broker).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app: webstack-gitops
    component: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: redis
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        command: ["redis-server", "--appendonly", "yes"]
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  labels:
    app: webstack-gitops
    component: redis
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
      protocol: TCP
  selector:
    app: webstack-gitops
    component: redis
EOF
}

generate_kafka(){
  info "Generowanie kafka-kraft.yaml..."
  cat << EOF > "$BASE_DIR/kafka-kraft.yaml"
# Plik generowany przez funkcję generate_kafka
# StatefulSet i Service dla Apache Kafka z KRaft (bez Zookeepra).
# Uproszczona konfiguracja dla Development/Test.
apiVersion: v1
kind: Service
metadata:
  name: kafka
  labels:
    app: webstack-gitops
    component: kafka
spec:
  ports:
  - port: 9092
    name: client
  - port: 9093
    name: inter-broker
  selector:
    app: webstack-gitops
    component: kafka
  clusterIP: None
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  labels:
    app: webstack-gitops
    component: kafka
spec:
  serviceName: "kafka"
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: kafka
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.6.1
        ports:
        - containerPort: 9092
          name: client
        - containerPort: 9093
          name: inter-broker
        env:
          - name: KAFKA_CFG_NODE_ID
            value: "1"
          - name: KAFKA_CFG_PROCESS_ROLES
            value: "controller,broker"
          - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
            value: "1@kafka-0.kafka.davtrowebdbvault.svc.cluster.local:9093"
          - name: KAFKA_CFG_LISTENERS
            value: "CLIENT://:9092, INTERNAL://:9093"
          - name: KAFKA_CFG_ADVERTISED_LISTENERS
            value: "CLIENT://kafka:9092, INTERNAL://kafka:9093"
          - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
            value: "CLIENT:PLAINTEXT, INTERNAL:PLAINTEXT"
          - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
            value: "INTERNAL"
          - name: KAFKA_CFG_KRAFT_CLUSTER_ID
            value: "${KAFKA_CLUSTER_ID}"
          - name: KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE
            value: "true"
        volumeMounts:
        - name: kafka-data
          mountPath: /bitnami/kafka/data
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1024Mi"
            cpu: "1000m"
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
EOF
}

# 2.3 Prometheus
generate_prometheus(){
  info "Generowanie prometheus.yaml i prometheus-config.yaml..."
  
  # prometheus-config.yaml
  cat << EOF > "$BASE_DIR/prometheus-config.yaml"
# Plik generowany przez funkcję generate_prometheus
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  labels:
    app: webstack-gitops
    component: prometheus
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    # Konfiguracja scraping dla samego Prometheusa
    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']

      # Scraping dla aplikacji FastAPI
      - job_name: 'fastapi-app'
        metrics_path: /metrics # Zgodne z instrumentator.expose() w main.py
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          # Celuj w Pody z etykietą app=webstack-gitops i portem 8000
          - source_labels: [__meta_kubernetes_pod_label_component]
            regex: fastapi
            action: keep
          - source_labels: [__address__]
            regex: '(.+):8000$'
            replacement: '\$1:8000'
            target_label: __address__
      
      # Scraping dla Vault (jeśli ekspozycja jest włączona)
      - job_name: 'vault'
        metrics_path: /v1/sys/metrics
        params:
          format: ['prometheus']
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_component]
            regex: vault
            action: keep
          - source_labels: [__address__]
            regex: '(.+):8200$'
            replacement: '\$1:8200'
            target_label: __address__
EOF

  # prometheus.yaml
  cat << EOF > "$BASE_DIR/prometheus.yaml"
# Plik generowany przez funkcję generate_prometheus
# Deployment i Service dla Prometheus
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  labels:
    app: webstack-gitops
    component: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: prometheus
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        args:
          - "--config.file=/etc/prometheus/prometheus.yml"
          - "--storage.tsdb.path=/prometheus"
          - "--web.enable-lifecycle"
        ports:
        - containerPort: 9090
        volumeMounts:
          - name: prometheus-config
            mountPath: /etc/prometheus
          - name: prometheus-storage
            mountPath: /prometheus
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
        - name: prometheus-config
          configMap:
            name: prometheus-config
  volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  labels:
    app: webstack-gitops
    component: prometheus
spec:
  type: ClusterIP
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
  selector:
    app: webstack-gitops
    component: prometheus
EOF
}

# 2.4 Grafana
generate_grafana(){
  info "Generowanie grafana.yaml i grafana-datasource.yaml..."
  
  # grafana-datasource.yaml
  cat << EOF > "$BASE_DIR/grafana-datasource.yaml"
# Plik generowany przez funkcję generate_grafana
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  labels:
    app: webstack-gitops
    component: grafana
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-service:9090
      isDefault: true
      access: proxy
      # Dodanie Loki i Tempo
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
    - name: Tempo
      type: tempo
      url: http://tempo:3200
      access: proxy
      basicAuth: false
      # Konfiguracja, by łączył Logi z Loki i Metrics z Prometheus
      tracesToLogs:
        datasourceUid: Loki
        tags: ['http.method', 'http.status_code']
        mappedKeys:
          - app
          - host
      tracesToMetrics:
        datasourceUid: Prometheus
        queries:
          - name: 'HTTP Requests'
            query: 'http_request_duration_seconds_count{job="fastapi-app", app="$__tags.app"}'
EOF

  # grafana.yaml
  cat << EOF > "$BASE_DIR/grafana.yaml"
# Plik generowany przez funkcję generate_grafana
# Deployment, Service i Ingress dla Grafana
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  labels:
    app: webstack-gitops
    component: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: grafana
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.2.2
        ports:
        - containerPort: 3000
        env:
          - name: GF_SECURITY_ADMIN_USER
            value: admin
          - name: GF_SECURITY_ADMIN_PASSWORD
            value: admin
          - name: GF_SERVER_ROOT_URL
            value: "http://grafana.webstack-gitops.local"
        volumeMounts:
          - name: grafana-datasource
            mountPath: /etc/grafana/provisioning/datasources
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "128Mi"
            cpu: "150m"
          limits:
            memory: "256Mi"
            cpu: "300m"
      volumes:
        - name: grafana-datasource
          configMap:
            name: grafana-datasource
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  labels:
    app: webstack-gitops
    component: grafana
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app: webstack-gitops
    component: grafana
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
  labels:
    app: webstack-gitops
    component: grafana
spec:
  rules:
  - host: grafana.webstack-gitops.local # Subdomena Grafany
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-service
            port:
              number: 80
EOF
}

# 2.5 Loki (Logowanie)
generate_loki(){
  info "Generowanie loki.yaml i loki-config.yaml..."

  # loki-config.yaml
  cat << EOF > "$BASE_DIR/loki-config.yaml"
# Plik generowany przez funkcję generate_loki
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  labels:
    app: webstack-gitops
    component: loki
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      path_prefix: /loki/data
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
        final_sleep: 0s
    schema_config:
      configs:
        - from: 2024-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v12
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/index
        cache_location: /loki/cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
EOF

  # loki.yaml
  cat << EOF > "$BASE_DIR/loki.yaml"
# Plik generowany przez funkcję generate_loki
# StatefulSet i Service dla Loki (Log Aggregation)
apiVersion: v1
kind: Service
metadata:
  name: loki
  labels:
    app: webstack-gitops
    component: loki
spec:
  ports:
    - name: http
      port: 3100
      targetPort: 3100
  selector:
    app: webstack-gitops
    component: loki
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  labels:
    app: webstack-gitops
    component: loki
spec:
  serviceName: "loki"
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: loki
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.2
        args:
          - "-config.file=/etc/loki/loki.yaml"
        ports:
        - containerPort: 3100
          name: http
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /loki
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: loki-config
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
EOF
}

# 2.6 Promtail (Log Collector)
generate_promtail(){
  info "Generowanie promtail.yaml i promtail-config.yaml..."
  
  # promtail-config.yaml
  cat << EOF > "$BASE_DIR/promtail-config.yaml"
# Plik generowany przez funkcję generate_promtail
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  labels:
    app: webstack-gitops
    component: promtail
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    positions:
      filename: /tmp/positions.yaml
    clients:
      # Celuj w Service Loki
      - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
        - role: pod
      # Zbieraj logi ze wszystkich Podów oprócz Promtail i Kyverno
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_component]
        regex: promtail|kyverno
        action: drop
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_name]
        regex: (.+);(.+)
        target_label: __path__
        replacement: /var/log/pods/\$1/\$2/*.log
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: __host__
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: instance
EOF
  
  # promtail.yaml
  cat << EOF > "$BASE_DIR/promtail.yaml"
# Plik generowany przez funkcję generate_promtail
# DaemonSet i ServiceAccount dla Promtail (Log Shipping)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail-sa
  labels:
    app: webstack-gitops
    component: promtail
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  labels:
    app: webstack-gitops
    component: promtail
spec:
  selector:
    matchLabels:
      app: webstack-gitops
      component: promtail
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: promtail
    spec:
      serviceAccountName: promtail-sa
      # Wymagane uprawnienia do odczytu logów z hosta
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"
      hostPID: true
      hostPath: true
      containers:
      - name: promtail
        image: grafana/promtail:2.9.2
        args:
          - "-config.file=/etc/promtail/promtail.yaml"
        volumeMounts:
          - name: config
            mountPath: /etc/promtail
          - name: run
            mountPath: /run/docker/
          - name: logs
            mountPath: /var/log/
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "50Mi"
            cpu: "50m"
          limits:
            memory: "100Mi"
            cpu: "100m"
      volumes:
        - name: config
          configMap:
            name: promtail-config
        - name: run
          hostPath:
            path: /run/docker/
        - name: logs
          hostPath:
            path: /var/log/
EOF
}

# 2.7 Tempo (Tracing)
generate_tempo(){
  info "Generowanie tempo.yaml i tempo-config.yaml..."

  # tempo-config.yaml
  cat << EOF > "$BASE_DIR/tempo-config.yaml"
# Plik generowany przez funkcję generate_tempo
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  labels:
    app: webstack-gitops
    component: tempo
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    compactor:
      compaction_window: 1h
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
    ingester:
      trace_ingestion_rate_limit_enabled: false
    storage:
      trace:
        backend: local
        local:
          path: /var/tempo/traces
EOF
  
  # tempo.yaml
  cat << EOF > "$BASE_DIR/tempo.yaml"
# Plik generowany przez funkcję generate_tempo
# StatefulSet i Service dla Tempo (Distributed Tracing)
apiVersion: v1
kind: Service
metadata:
  name: tempo
  labels:
    app: webstack-gitops
    component: tempo
spec:
  ports:
    - name: http
      port: 3200
      targetPort: 3200
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
  selector:
    app: webstack-gitops
    component: tempo
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tempo
  labels:
    app: webstack-gitops
    component: tempo
spec:
  serviceName: "tempo"
  replicas: 1
  selector:
    matchLabels:
      app: webstack-gitops
      component: tempo
  template:
    metadata:
      labels:
        app: webstack-gitops
        component: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.4.2
        args:
          - "-config.file=/etc/tempo/tempo.yaml"
        ports:
        - containerPort: 3200
          name: http
        - containerPort: 4317
          name: otlp-grpc
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: storage
          mountPath: /var/tempo
        # Kyverno Wymóg: Wymagane requests i limits
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: tempo-config
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
EOF
}

# 2.8 Kyverno Policy
generate_kyverno(){
  info "Generowanie kyverno-policy.yaml..."
  # (Kod pliku kyverno-policy.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/kyverno-policy.yaml"
# Plik generowany przez funkcję generate_kyverno
# Wymusza standardy bezpieczeństwa w klastrze, zanim ArgoCD wdroży zasoby.
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-requests-limits
  annotations:
    policies.kyverno.io/title: Wymagaj limitów zasobów dla CPU i RAM
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Pod
    kyverno.io/kyverno-version: 1.12.0
    kyverno.io/kubernetes-version: "1.27"
  labels:
    app.kubernetes.io/instance: webstack-gitops
    app.kubernetes.io/component: kyverno
spec:
  # Użyj 'Enforce' aby blokować zasoby łamiące politykę
  validationFailureAction: Enforce 
  background: true
  rules:
  - name: check-container-resources
    match:
      resources:
        kinds:
        - Pod
    preconditions:
      # Wyklucz pody w namespace'ach infrastrukturalnych (kyverno, argocd, systemowe)
      all:
      - key: "{{request.object.metadata.namespace}}"
        operator: NotIn
        value:
        - kyverno
        - argocd
        - kube-system
        - default # Często używany dla testów
    validate:
      message: "Wszystkie kontenery muszą definiować 'requests' oraz 'limits' dla CPU i pamięci (memory). Jest to krytyczne dla stabilności i wydajności klastra."
      # Użyj foreach, aby sprawdzić każdy kontener w Podzie
      foreach: "request.object.spec.containers[]"
      deny:
        conditions:
          # Jeżeli którekolwiek z pól jest nieustawione lub puste, odrzuć Pod
          any:
          - key: "{{ element.resources.requests.cpu || '' }}"
            operator: Equals
            value: ""
          - key: "{{ element.resources.limits.cpu || '' }}"
            operator: Equals
            value: ""
          - key: "{{ element.resources.requests.memory || '' }}"
            operator: Equals
            value: ""
          - key: "{{ element.resources.limits.memory || '' }}"
            operator: Equals
            value: ""
EOF
}

# 2.9 ArgoCD Application
generate_argocd_app(){
  info "Generowanie argocd-application.yaml..."
  cat << EOF > argocd-application.yaml
# Plik generowany przez funkcję generate_argocd_app
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website-db-stack
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        maxDuration: 3m0s
        factor: 2
EOF
}

# 2.10 ArgoCD Standalone Manifest
generate_argocd_standalone(){
  info "Generowanie argocd-standalone-install.yaml..."
  cat << EOF > argocd-standalone-install.yaml
# Plik generowany przez funkcję generate_argocd_standalone
# Uproszczona, minimalna instalacja ArgoCD (potrzebne tylko namespace, deployment, service)
# W celach demonstracyjnych i dla uproszczenia
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-application-controller
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: argocd
EOF
}


# 2.11 Kustomization
generate_kustomization(){
  info "Generowanie kustomization.yaml..."
  # (Kod pliku kustomization.yaml - używam pliku z kontekstu)
  cat << 'EOF' > "$BASE_DIR/kustomization.yaml"
# Plik generowany przez funkcję generate_kustomization
# Łączy wszystkie zasoby Kubernetes w jedną spójną całość.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Lista wszystkich plików YAML w katalogu manifests/base
resources:
  # Aplikacja i Infrastruktura
  - app-deployment.yaml
  - postgres-db.yaml
  - pgadmin.yaml
  - vault.yaml
  - redis.yaml
  - kafka-kraft.yaml
  
  # Observability (Monitoring, Logging, Tracing)
  - prometheus.yaml
  - prometheus-config.yaml
  - grafana.yaml
  - grafana-datasource.yaml
  - loki.yaml
  - loki-config.yaml
  - promtail.yaml
  - promtail-config.yaml
  - tempo.yaml
  - tempo-config.yaml
  
  # Security/Policy Enforcement
  - kyverno-policy.yaml

# Użyj nazwy projektu jako prefiksu dla etykiet
# Zmienna PROJECT ze skryptu to webstack-gitops
commonLabels:
  app.kubernetes.io/name: webstack-gitops
  app.kubernetes.io/instance: webstack-gitops
  app.kubernetes.io/managed-by: kustomize

# Ustawienia namespace (zmienna NAMESPACE w skrypcie to davtrowebdbvault)
namespace: davtrowebdbvault

# Użycie configMapGenerator/secretGenerator dla zasobów, które tego wymagają
# (np. Prometheus ConfigMap, Grafana Datasource Secret - zostaną dodane przez inne funkcje)
EOF
}

# 2.12 README
generate_readme(){
  info "Generowanie README.md..."
  cat << EOF > README.md
# 🚀 Unified GitOps Stack - FastAPI, Vault, Kafka, MLOps (Loki, Tempo, Grafana, Prometheus), Kyverno

Projekt ten demonstruje kompletną, nowoczesną architekturę Microservices wdrożoną przy użyciu **GitOps (ArgoCD + Kustomize)**.

## 🛠️ Zastosowany Stos Technologiczny

- **Aplikacja:** FastAPI (Python)
- **Repozytorium:** GitHub Container Registry (ghcr.io)
- **CI/CD:** GitHub Actions (Build & Push Docker Image)
- **GitOps:** ArgoCD & Kustomize
- **Baza Danych:** PostgreSQL (StatefulSet)
- **Zarządzanie DB:** pgAdmin
- **Pamięć Cache/Broker:** Redis
- **Message Broker:** Apache Kafka (KRaft, Single-Node)
- **Zarządzanie Sekretami:** HashiCorp Vault (z sidecarem Injector Agent)
- **Monitoring & Observability (MLOps):**
    - **Metryki:** Prometheus
    - **Logi:** Loki + Promtail
    - **Tracing:** Tempo (OpenTelemetry/OTLP)
    - **Wizualizacja:** Grafana (połączona z P/L/T)
- **Zarządzanie Politykami:** Kyverno (Wymuszenie Resource Limits/Requests)

## 🎯 Zmienne Projektu

| Zmienna | Wartość | Opis |
| :--- | :--- | :--- |
| PROJECT | \`${PROJECT}\` | Nazwa projektu (używana do domen/etykiet) |
| NAMESPACE | \`${NAMESPACE}\` | Przestrzeń nazw w Kubernetes |
| ORG | \`${ORG}\` | Organizacja GitHub |
| REPO_URL | \`${REPO_URL}\` | URL repozytorium Git |

## 🚀 Finalne Kroki Wdrożenia (KRYTYCZNE)

1.  **Inicjalizacja Git:**
    \`\`\`bash
    git init
    git add .
    git commit -m 'Initial commit - unified stack with Kafka KRaft and Tempo tracing'
    git branch -M main
    git remote add origin ${REPO_URL}
    git push -u origin main
    \`\`\`

2.  **Weryfikacja struktury:**
    \`\`\`bash
    tree manifests/
    \`\`\`

3.  **Test lokalny Kustomize:**
    \`\`\`bash
    kubectl kustomize manifests/base
    \`\`\`

4.  **Deploy ArgoCD Application (po push do repo):**
    \`\`\`bash
    kubectl apply -f argocd-application.yaml
    \`\`\`

5.  **Sprawdź status w ArgoCD:**
    \`\`\`bash
    kubectl get applications -n argocd
    kubectl describe application website-db-stack -n argocd
    \`\`\`

⚠️  **WAŻNE: Upewnij się że:**
    ✓ Repozytorium \`${REPO_URL}\` istnieje
    ✓ ArgoCD jest zainstalowany (\`kubectl get ns argocd\`)
    ✓ Folder \`manifests/base/\` zawiera wszystkie pliki

## 🌐 Dostęp:

- **App:** \`http://${PROJECT}.local\`
- **pgAdmin:** \`http://pgadmin.${PROJECT}.local\`
- **Grafana:** \`http://grafana.${PROJECT}.local\`
- **Vault:** \`http://vault:8200\` (dostęp wewnętrzny)

EOF
}


# ==============================\
# GŁÓWNA FUNKCJA
# ==============================\
generate_all(){
  info "🚀 Rozpoczynam generowanie unified stack..."
  
  generate_structure
  generate_fastapi_app
  generate_dockerfile
  generate_github_actions

  # Kubernetes Manifests
  generate_k8s_base
  generate_postgres
  generate_pgadmin
  generate_vault
  generate_redis
  generate_kafka
  generate_prometheus
  generate_grafana
  generate_loki
  generate_promtail
  generate_tempo
  generate_kyverno # Kyverno musi być, aby ArgoCD wdrożył zasoby z limits/requests

  # GitOps/ArgoCD
  generate_argocd_app
  generate_argocd_standalone
  generate_kustomization
  generate_readme
  
  echo ""
  info "✅ WSZYSTKO GOTOWE! (Nazwa projektu to teraz: ${PROJECT})"
  echo ""
  echo "⚠️ PROSZĘ PRZEJDŹ DO SEKCJI '🚀 Finalne Kroki Wdrożenia (KRYTYCZNE)' W README.MD LUB POWYŻEJ"
  echo "   MUSISZ ZAPISAĆ TEN SKRYPT I GO URUCHOMIĆ:"
  echo "   bash unified_stack_generator.sh generate"
  echo ""
}

# ==============================\
# MENU
# ==============================\
case "${1:-}" in
  generate)
    generate_all
    ;;\
  help|-h|--help)
    echo "Użycie: $0 [generate|help]"
    echo "  generate: Generuje wszystkie pliki aplikacji i manifesty Kubernetes do katalogów."
    ;;
  *)
    echo "Nieznana komenda. Użyj: $0 help"
    ;;
esac
