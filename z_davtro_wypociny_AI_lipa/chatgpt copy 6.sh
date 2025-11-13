#!/usr/bin/env bash
set -euo pipefail
###############################################################################
PROJECT="website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui"
NAMESPACE="davtrowebdbvault"
REGISTRY="${REGISTRY:-ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui}"
REPO_URL="${REPO_URL:-https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.git}"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-4mUj5vFk3tW7pY0iH2gR8qL6eD9oB1cZ}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${ROOT_DIR}/app"
TEMPLATES_DIR="${APP_DIR}/templates"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"

echo "=== 0. Sprawdzamy MicroK8s ==="
sudo microk8s status --wait-ready >/dev/null
sudo microk8s enable dns ingress storage registry helm3 metrics-server

echo "=== 1. Tworzymy katalogi ==="
mkdir -p "$TEMPLATES_DIR" "$BASE_DIR" "$WORKFLOW_DIR"

echo "=== 2. Generujemy FastAPI (main.py) ==="
cat > "${APP_DIR}/main.py" <<'PY'
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import psycopg2, os, logging, time, hvac
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

app = FastAPI(title="Dawid Trojanowski – Strona Osobista")
templates = Jinja2Templates(directory="templates")
Instrumentator().instrument(app).expose(app)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_vault_secret(path: str) -> dict:
    try:
        client = hvac.Client(url=os.getenv("VAULT_ADDR","http://vault:8200"),
                             token=os.getenv("VAULT_TOKEN"))
        return client.read(path)['data']['data']
    except: return {}

def get_db_connection():
    for _ in range(30):
        try: return psycopg2.connect(os.getenv("DATABASE_URL","dbname=appdb user=appuser password=Str0ngP@ss host=postgres-db"))
        except: time.sleep(10)
    raise RuntimeError("DB unreachable")

@app.on_event("startup")
def init():
    con=get_db_connection(); cur=con.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS survey_responses(id SERIAL PRIMARY KEY,question TEXT,answer TEXT,created_at TIMESTAMP DEFAULT NOW())")
    cur.execute("CREATE TABLE IF NOT EXISTS page_visits(id SERIAL PRIMARY KEY,page VARCHAR(255),visited_at TIMESTAMP DEFAULT NOW())")
    cur.execute("CREATE TABLE IF NOT EXISTS contact_messages(id SERIAL PRIMARY KEY,email VARCHAR(255),message TEXT,created_at TIMESTAMP DEFAULT NOW())")
    con.commit(); cur.close(); con.close()

@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    con=get_db_connection(); cur=con.cursor()
    cur.execute("INSERT INTO page_visits(page) VALUES ('home')"); con.commit(); cur.close(); con.close()
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/health")
def health():
    con=get_db_connection(); cur=con.cursor(); cur.execute("SELECT 1"); cur.close(); con.close()
    return {"status":"healthy","vault":"connected" if get_vault_secret("secret/data/database/postgres") else "disconnected"}

@app.get("/api/survey/questions")
def questions():
    return [
        {"id":1,"text":"Jak oceniasz design strony?","type":"rating","options":["1 - Słabo","2","3","4","5 - Doskonale"]},
        {"id":2,"text":"Czy informacje były przydatne?","type":"choice","options":["Tak","Raczej tak","Nie wiem","Raczej nie","Nie"]},
        {"id":3,"text":"Jakie technologie Cię zainteresowały?","type":"multiselect","options":["Python","JavaScript","React","Kubernetes","Docker","PostgreSQL","Vault"]},
        {"id":4,"text":"Czy poleciłbyś tę stronę innym?","type":"choice","options":["Zdecydowanie tak","Prawdopodobnie tak","Nie wiem","Raczej nie","Zdecydowanie nie"]},
        {"id":5,"text":"Co sądzisz o portfolio?","type":"text","placeholder":"Podziel się swoją opinią..."}
    ]

class SurveyResponse(BaseModel): question: str; answer: str
@app.post("/api/survey/submit")
def submit(sr: SurveyResponse):
    con=get_db_connection(); cur=con.cursor()
    cur.execute("INSERT INTO survey_responses(question,answer) VALUES (%s,%s)",(sr.question,sr.answer))
    con.commit(); cur.close(); con.close()
    return {"status":"success","message":"Dziękujemy za wypełnienie ankiety!"}

@app.get("/api/survey/stats")
def stats():
    con=get_db_connection(); cur=con.cursor()
    cur.execute("SELECT question,answer,COUNT(*) FROM survey_responses GROUP BY question,answer")
    rows=cur.fetchall(); cur.close(); con.close()
    out={}
    for q,a,c in rows:
        if q not in out: out[q]=[]
        out[q].append({"answer":a,"count":c})
    return {"survey_responses":out,"total_visits":0,"total_responses":sum(len(v) for v in out.values())}

@app.post("/api/contact")
def contact(email: str = Form(...), message: str = Form(...)):
    con=get_db_connection(); cur=con.cursor()
    cur.execute("INSERT INTO contact_messages(email,message) VALUES (%s,%s)",(email,message))
    con.commit(); cur.close(); con.close()
    return {"status":"success","message":"Wiadomość została wysłana!"}

if __name__=="__main__":
    import uvicorn
    uvicorn.run(app,host="0.0.0.0",port=8000)
PY

echo "=== 3. Generujemy requirements.txt ==="
cat > "${APP_DIR}/requirements.txt" <<EOF
fastapi==0.110.0
uvicorn[standard]==0.27.1
psycopg2-binary==2.9.9
jinja2==3.1.3
prometheus-fastapi-instrumentator==6.1.0
hvac==2.1.0
EOF

echo "=== 4. Generujemy Dockerfile ==="
cat > "${APP_DIR}/Dockerfile" <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
EOF

echo "=== 5. Generujemy index.html ==="
cat > "${TEMPLATES_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <title>Dawid Trojanowski</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white">
  <div class="container mx-auto p-8 text-center">
    <h1 class="text-4xl font-bold text-purple-300">Dawid Trojanowski</h1>
    <p class="mt-4 text-gray-300">FastAPI + Kubernetes + Vault + GitOps = ❤️</p>
    <div class="mt-8">
      <a href="/api/survey/questions" class="px-4 py-2 bg-purple-600 rounded hover:bg-purple-700">Sprawdź API ankiety</a>
    </div>
  </div>
</body>
</html>
HTML

echo "=== 6. Generujemy GitHub Actions workflow ==="
cat > "${WORKFLOW_DIR}/build-push.yaml" <<EOF
name: build-push
on:
  push:
    branches: [main]
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${REGISTRY}/app
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: \${{ env.REGISTRY }}
          username: \${{ github.actor }}
          password: \${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: \${{ env.REGISTRY }}\${{ env.IMAGE_NAME }}
      - uses: docker/build-push-action@v5
        with:
          context: app
          push: true
          tags: \${{ steps.meta.outputs.tags }}
          labels: \${{ steps.meta.outputs.labels }}
EOF

echo "=== 7. Generujemy wszystkie manifesty (katalog base) ==="
mkdir -p "${BASE_DIR}"

# kustomization
cat > "${BASE_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - ns.yaml
  - vault.yaml
  - kyverno.yaml
  - postgres.yaml
  - redis.yaml
  - kafka-kraft.yaml
  - kafka-ui.yaml
  - pgadmin.yaml
  - app.yaml
  - prometheus.yaml
  - grafana.yaml
  - loki.yaml
  - promtail.yaml
  - tempo.yaml
  - ingress.yaml
EOF

# ns.yaml
cat > "${BASE_DIR}/ns.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

# vault
cat > "${BASE_DIR}/vault.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  VAULT_ADDR: http://vault.${NAMESPACE}.svc:8200
  VAULT_TOKEN: root
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  selector:
    app: vault
  ports:
  - port: 8200
    targetPort: 8200
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: vault }
  template:
    metadata:
      labels: { app: vault }
    spec:
      containers:
      - name: vault
        image: vault:1.16
        args: [ "server", "-dev", "-dev-root-token-id=root" ]
        ports: [{ containerPort: 8200 }]
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: root
EOF

# kyverno
cat > "${BASE_DIR}/kyverno.yaml" <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-labels
    match:
      resources:
        kinds: [Deployment,StatefulSet,DaemonSet]
    validate:
      message: "Label 'app' is required."
      pattern:
        metadata:
          labels:
            app: "?*"
EOF

# postgres
cat > "${BASE_DIR}/postgres.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: ${NAMESPACE}
data:
  init.sql: |
    CREATE DATABASE appdb;
    CREATE USER appuser WITH ENCRYPTED PASSWORD 'Str0ngP@ss';
    GRANT ALL PRIVILEGES ON DATABASE appdb TO appuser;
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
spec:
  serviceName: postgres-db
  replicas: 1
  selector:
    matchLabels: { app: postgres-db }
  template:
    metadata:
      labels: { app: postgres-db }
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports: [{ containerPort: 5432 }]
        env:
        - { name: POSTGRES_DB, value: postgres }
        - { name: POSTGRES_USER, value: postgres }
        - { name: POSTGRES_PASSWORD, value: Str0ngP@ss }
        volumeMounts:
        - { name: data, mountPath: /var/lib/postgresql/data }
        - { name: init, mountPath: /docker-entrypoint-initdb.d }
      volumes:
      - { name: init, configMap: { name: postgres-init } }
  volumeClaimTemplates:
  - metadata: { name: data }
    spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 5Gi } } }
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
spec:
  selector: { app: postgres-db }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF

# redis
cat > "${BASE_DIR}/redis.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels: { app: redis }
  template:
    metadata:
      labels: { app: redis }
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports: [{ containerPort: 6379 }]
        command: ["redis-server","--save","60","1"]
        volumeMounts: [{ name: data, mountPath: /data }]
  volumeClaimTemplates:
  - metadata: { name: data }
    spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 2Gi } } }
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  selector: { app: redis }
  ports: [{ port: 6379, targetPort: 6379 }]
EOF

# kafka-kraft
cat > "${BASE_DIR}/kafka-kraft.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-kraft-config
  namespace: ${NAMESPACE}
data:
  server.properties: |
    process.roles=broker,controller
    node.id=1
    controller.quorum.voters=1@kafka-kraft-0.kafka-kraft-headless:9093
    listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
    advertised.listeners=PLAINTEXT://kafka-kraft-0.kafka-kraft-headless:9092
    controller.listener.names=CONTROLLER
    listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
    log.dirs=/var/lib/kafka/data
    offsets.topic.replication.factor=1
    transaction.state.log.replication.factor=1
    transaction.state.log.min.isr=1
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-kraft
  namespace: ${NAMESPACE}
spec:
  serviceName: kafka-kraft-headless
  replicas: 1
  selector:
    matchLabels: { app: kafka-kraft }
  template:
    metadata:
      labels: { app: kafka-kraft }
    spec:
      containers:
      - name: kafka
        image: apache/kafka:3.7.0
        ports:
        - { name: plain, containerPort: 9092 }
        - { name: controller, containerPort: 9093 }
        env: [ { name: CLUSTER_ID, value: "${KAFKA_CLUSTER_ID}" } ]
        command: ["/bin/bash","-c","sed 's/cluster.id=/cluster.id=\\${CLUSTER_ID}/' /etc/kafka/server.properties > /tmp/s.properties && /etc/kafka/docker/run"]
        volumeMounts:
        - { name: data, mountPath: /var/lib/kafka }
        - { name: config, mountPath: /etc/kafka }
      volumes:
      - { name: config, configMap: { name: kafka-kraft-config } }
  volumeClaimTemplates:
  - metadata: { name: data }
    spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 10Gi } } }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft-headless
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  selector: { app: kafka-kraft }
  ports:
  - { name: plain, port: 9092, targetPort: 9092 }
  - { name: controller, port: 9093, targetPort: 9093 }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  namespace: ${NAMESPACE}
spec:
  selector: { app: kafka-kraft }
  ports:
  - { name: plain, port: 9092, targetPort: 9092 }
EOF

# kafka-ui
cat > "${BASE_DIR}/kafka-ui.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: kafka-ui }
  template:
    metadata:
      labels: { app: kafka-ui }
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        ports: [{ containerPort: 8080 }]
        env:
        - { name: KAFKA_CLUSTERS_0_NAME, value: davtro }
        - { name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS, value: kafka-kraft:9092 }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
spec:
  selector: { app: kafka-ui }
  ports: [{ port: 8080, targetPort: 8080 }]
EOF

# pgadmin
cat > "${BASE_DIR}/pgadmin.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: pgadmin }
  template:
    metadata:
      labels: { app: pgadmin }
    spec:
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:8
        ports: [{ containerPort: 80 }]
        env:
        - { name: PGADMIN_DEFAULT_EMAIL, value: admin@example.com }
        - { name: PGADMIN_DEFAULT_PASSWORD, value: admin }
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
spec:
  selector: { app: pgadmin }
  ports: [{ port: 80, targetPort: 80 }]
EOF

# prometheus
cat > "${BASE_DIR}/prometheus.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
data:
  prometheus.yml: |
    global: { scrape_interval: 15s }
    scrape_configs:
    - job_name: 'app'
      static_configs: [ { targets: ['app-deployment:8000'] } ]
    - job_name: 'postgres'
      static_configs: [ { targets: ['postgres-db:5432'] } ]
    - job_name: 'redis'
      static_configs: [ { targets: ['redis:6379'] } ]
    - job_name: 'kafka'
      static_configs: [ { targets: ['kafka-kraft:9092'] } ]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: prometheus }
  template:
    metadata:
      labels: { app: prometheus }
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.51.0
        args: ["--config.file=/etc/prometheus/prometheus.yml","--storage.tsdb.path=/prometheus"]
        ports: [{ containerPort: 9090 }]
        volumeMounts:
        - { name: config, mountPath: /etc/prometheus }
        - { name: data, mountPath: /prometheus }
      volumes:
      - { name: config, configMap: { name: prometheus-config } }
      - { name: data, emptyDir: {} }
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  selector: { app: prometheus }
  ports: [{ port: 9090, targetPort: 9090 }]
EOF

# grafana
cat > "${BASE_DIR}/grafana.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-datasource
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
      access: proxy
      isDefault: true
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
    - name: Tempo
      type: tempo
      url: http://tempo:3200
      access: proxy
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: grafana }
  template:
    metadata:
      labels: { app: grafana }
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.4.0
        ports: [{ containerPort: 3000 }]
        env:
        - { name: GF_SECURITY_ADMIN_USER, value: admin }
        - { name: GF_SECURITY_ADMIN_PASSWORD, value: admin }
        volumeMounts:
        - { name: ds, mountPath: /etc/grafana/provisioning/datasources }
      volumes:
      - { name: ds, secret: { secretName: grafana-datasource } }
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  selector: { app: grafana }
  ports: [{ port: 3000, targetPort: 3000 }]
EOF

# loki
cat > "${BASE_DIR}/loki.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
data:
  loki.yaml: |
    auth_enabled: false
    server: { http_listen_port: 3100 }
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring: { kvstore: { store: inmemory }, replication_factor: 1 }
      chunk_idle_period: 5m
      chunk_retain_period: 30s
    schema_config:
      configs: [ { from: "2020-05-15", store: boltdb, object_store: filesystem, schema: v11, index: { prefix: index_, period: 168h } } ]
    storage_config:
      boltdb: { directory: /tmp/loki/index }
      filesystem: { directory: /tmp/loki/chunks }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: loki }
  template:
    metadata:
      labels: { app: loki }
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.6
        args: ["-config.file=/etc/loki/loki.yaml"]
        ports: [{ containerPort: 3100 }]
        volumeMounts:
        - { name: config, mountPath: /etc/loki }
      volumes:
      - { name: config, configMap: { name: loki-config } }
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  selector: { app: loki }
  ports: [{ port: 3100, targetPort: 3100 }]
EOF

# promtail
cat > "${BASE_DIR}/promtail.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: ${NAMESPACE}
data:
  promtail.yaml: |
    server: { http_listen_port: 9080 }
    positions: { filename: /tmp/positions.yaml }
    clients: [ { url: http://loki:3100/loki/api/v1/push } ]
    scrape_configs:
    - job_name: pods
      kubernetes_sd_configs: [ { role: pod, namespaces: { names: [${NAMESPACE}] } } ]
      relabel_configs:
      - { source_labels: [__meta_kubernetes_pod_name], target_label: pod }
      - { source_labels: [__meta_kubernetes_pod_container_name], target_label: container }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels: { app: promtail }
  template:
    metadata:
      labels: { app: promtail }
    spec:
      containers:
      - name: promtail
        image: grafana/promtail:2.9.6
        args: ["-config.file=/etc/promtail/promtail.yaml"]
        volumeMounts:
        - { name: config, mountPath: /etc/promtail }
        - { name: varlog, mountPath: /var/log }
        - { name: varlibdocker, mountPath: /var/lib/docker/containers, readOnly: true }
      tolerations: [ { operator: Exists } ]
      volumes:
      - { name: config, configMap: { name: promtail-config } }
      - { name: varlog, hostPath: { path: /var/log } }
      - { name: varlibdocker, hostPath: { path: /var/lib/docker/containers } }
EOF

# tempo
cat > "${BASE_DIR}/tempo.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
data:
  tempo.yaml: |
    server: { http_listen_port: 3200 }
    distributor:
      receivers:
        jaeger:
          protocols: { thrift_http: {} }
    ingester: { trace_idle_period: 10s }
    storage:
      trace: { backend: local, local: { path: /tmp/tempo/traces } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: tempo }
  template:
    metadata:
      labels: { app: tempo }
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.4.0
        args: ["-config.file=/etc/tempo/tempo.yaml"]
        ports:
        - { name: http, containerPort: 3200 }
        - { name: jaeger-thrift, containerPort: 14268 }
        volumeMounts:
        - { name: config, mountPath: /etc/tempo }
      volumes:
      - { name: config, configMap: { name: tempo-config } }
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  selector: { app: tempo }
  ports:
  - { name: http, port: 3200, targetPort: 3200 }
  - { name: jaeger-thrift, port: 14268, targetPort: 14268 }
EOF

# app
cat > "${BASE_DIR}/app.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: { app: app-deployment }
  template:
    metadata:
      labels: { app: app-deployment }
    spec:
      containers:
      - name: app
        image: \${REGISTRY}/app:main
        ports: [{ containerPort: 8000 }]
        env:
        - { name: DATABASE_URL, value: "dbname=appdb user=appuser password=Str0ngP@ss host=postgres-db" }
        - { name: VAULT_ADDR, value: "http://vault.${NAMESPACE}.svc:8200" }
        livenessProbe:
          httpGet: { path: /health, port: 8000 }
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          httpGet: { path: /health, port: 8000 }
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: app-deployment
  namespace: ${NAMESPACE}
spec:
  selector: { app: app-deployment }
  ports:
  - { name: http, port: 8000, targetPort: 8000 }
EOF

# ingress
cat > "${BASE_DIR}/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${PROJECT}-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: davtro.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-deployment
            port:
              number: 8000
EOF

echo "=== 8. Namespace ${NAMESPACE} ==="
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo "=== 9. Apply baza (Vault, postgres, redis, kafka, monitoring) ==="
kubectl apply -k "${BASE_DIR}"

echo "=== 10. Inicjalizacja Vault ==="
kubectl wait --for=condition=ready pod -l app=vault -n ${NAMESPACE} --timeout=120s
kubectl exec -n ${NAMESPACE} deployment/vault -- vault secrets enable -path=dattro kv-v2 || true
kubectl exec -n ${NAMESPACE} deployment/vault -- vault kv put davtro/db-secret postgres-db=appdb postgres-user=appuser postgres-password=Str0ngP@ss postgres-host=postgres-db || true

echo "=== 11. Budujemy i pushujemy obraz (lokalny rejestr) ==="
cd "${APP_DIR}"
sudo microk8s ctr image import <(docker build -q -t localhost:32000/dattro-app:latest .)
docker tag localhost:32000/dattro-app:latest localhost:32000/dattro-app:latest
docker push localhost:32000/dattro-app:latest || true   # jeśli GHCR – niepotrzebne
cd "${ROOT_DIR}"

echo "=== 12. ArgoCD – aplikujemy Application który BĘDZIE CIĄGLE WDRAŻAŁ repo ==="
cat > /tmp/argocd-app.yaml <<EOF
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
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - ServerSideApply=true
    retry:
      limit: 5
      backoff: { duration: 5s, factor: 2, maxDuration: 3m }
EOF
kubectl apply -f /tmp/argocd-app.yaml

echo "=== 13. Czekamy na zdrowie aplikacji ==="
kubectl wait --for=condition=ready pod -l app=app-deployment -n ${NAMESPACE} --timeout=300s || true

echo "=== 14. Port-forwards (opcjonalnie) ==="
echo "ArgoCD    : kubectl port-forward -n argocd svc/argocd-server 8080:443  → admin/$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "Grafana   : kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000  → admin/admin"
echo "App       : kubectl port-forward -n ${NAMESPACE} svc/app-deployment 8000:8000  → http://localhost:8000"
echo "PgAdmin   : kubectl port-forward -n ${NAMESPACE} svc/pgadmin 8081:80"
echo "Kafka-UI  : kubectl port-forward -n ${NAMESPACE} svc/kafka-ui 8082:8080"
echo
echo "=== GOTOWE – ArgoCD będzie CIĄGLE synchronizował repo z klastrem! ==="
echo "Dodaj do /etc/hosts:  127.0.0.1  davtro.local   i wejdź: http://davtro.local"