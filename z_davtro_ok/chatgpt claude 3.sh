# ==============================
# STANDALONE ARGOCD APP (do apply z CLI)
# ==============================
generate_argocd_standalone(){
  info "Generowanie standalone ArgoCD Application (poza kustomization)..."
  cat > "${ROOT_DIR}/argocd-application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
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
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

  # Dodatkowo - wersja dla UI ArgoCD (JSON/YAML do wklejenia)
  cat > "${ROOT_DIR}/argocd-ui-paste.yaml" <<EOF
# =====================================================
# WKLEJ TO W UI ARGOCD (Edit as YAML)
# =====================================================
# Repository: ${REPO_URL}
# Namespace: ${NAMESPACE}
# =====================================================

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
spec:
  project: default
  source:
    repoURL: '${REPO_URL}'
    targetRevision: main
    path: manifests/base
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
}
#!/bin/bash
set -e

echo "🔍 Weryfikacja przed deployment do ArgoCD..."
echo ""

# 1. Sprawdź czy jesteśmy w git repo
if [ ! -d .git ]; then
    echo "❌ Nie jesteś w repozytorium Git!"
    echo "   Uruchom: git init"
    exit 1
fi
echo "✅ Git repo istnieje"

# 2. Sprawdź czy są commity
if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "❌ Brak commitów!"
    echo "   Uruchom: git add . && git commit -m 'init'"
    exit 1
fi
echo "✅ Commity istnieją"

# 3. Sprawdź czy jest remote
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "❌ Brak remote origin!"
    echo "   Uruchom: git remote add origin <URL>"
    exit 1
fi
REMOTE=$(git remote get-url origin)
echo "✅ Remote origin: $REMOTE"

# 4. Sprawdź czy wypushowano
LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "none")
REMOTE_BRANCH=$(git rev-parse origin/$(git branch --show-current) 2>/dev/null || echo "none")

if [ "$LOCAL" != "$REMOTE_BRANCH" ]; then
    echo "⚠️  UWAGA: Lokalne zmiany nie są wypushowane!"
    echo "   Uruchom: git push -u origin main"
    echo ""
    echo "   Lokalna wersja:  $LOCAL"
    echo "   Remote wersja:   $REMOTE_BRANCH"
    exit 1
fi
echo "✅ Zmiany wypushowane do remote"

# 5. Sprawdź czy manifests/base istnieje
if [ ! -d manifests/base ]; then
    echo "❌ Folder manifests/base/ nie istnieje!"
    exit 1
fi
echo "✅ Folder manifests/base/ istnieje"

# 6. Sprawdź czy kustomization.yaml istnieje
if [ ! -f manifests/base/kustomization.yaml ]; then
    echo "❌ Brak manifests/base/kustomization.yaml!"
    exit 1
fi
echo "✅ kustomization.yaml istnieje"

# 7. Test kustomize
echo ""
echo "🧪 Test Kustomize build..."
if kubectl kustomize manifests/base >/dev/null 2>&1; then
    echo "✅ Kustomize build sukces!"
else
    echo "❌ Kustomize build FAILED!"
    echo ""
    echo "Sprawdź błędy:"
    kubectl kustomize manifests/base
    exit 1
fi

# 8. Podsumowanie
echo ""
echo "================================================"
echo "✅ WSZYSTKO GOTOWE DO DEPLOYMENT W ARGOCD!"
echo "================================================"
echo ""
echo "Repository: $REMOTE"
echo "Branch: $(git branch --show-current)"
echo "Commit: $(git rev-parse --short HEAD)"
echo ""
echo "Następne kroki:"
echo "1. Otwórz ArgoCD UI"
echo "2. Kliknij '+ NEW APP'"
echo "3. Wklej zawartość z: argocd-ui-paste.yaml"
echo "4. LUB użyj: kubectl apply -f argocd-application.yaml"
echo ""
VERIFY
  chmod +x "${ROOT_DIR}/verify-before-argocd.sh"
}

# ==============================
# QUICK START GUIDE
# ==============================
generate_quickstart(){
  info "Generowanie quick start guide..."
  cat > "${ROOT_DIR}/QUICKSTART.md" <<'QS'
# 🚀 Quick Start Guide

## Krok 1: Wygeneruj wszystko
```bash
chmod +x unified-deployment.sh
./unified-deployment.sh generate
```

## Krok 2: Utwórz repo na GitHub
1. Idź na https://github.com/new
2. Nazwa: `website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin`
3. Ustaw jako **Public** (lub Private z odpowiednimi credentials)
4. **NIE** inicjalizuj z README/LICENSE/.gitignore
5. Kliknij **Create repository**

## Krok 3: Push do GitHub
```bash
# Dostosuj USERNAME do swojego
GITHUB_USERNAME="exea-centrum"
REPO_NAME="website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin"

git init
git add .
git commit -m "Initial commit: unified deployment stack"
git branch -M main
git remote add origin "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git push -u origin main
```

## Krok 4: Weryfikuj przed ArgoCD
```bash
./verify-before-argocd.sh
```

Jeśli zobaczysz "✅ WSZYSTKO GOTOWE" - możesz przejść dalej!

## Krok 5a: Deploy przez ArgoCD UI

### Metoda 1: Edit as YAML
1. Otwórz ArgoCD UI
2. Kliknij **+ NEW APP**
3. Kliknij **EDIT AS YAML** (prawy górny róg)
4. Skopiuj zawartość z `argocd-ui-paste.yaml`
5. **ZMIEŃ** `repoURL` na swoje repo!
6. Kliknij **SAVE**
7. Kliknij **CREATE**

### Metoda 2: Formularz
1. Application#!/usr/bin/env bash
set -euo pipefail

# Unified deployment script - combines website app with full GitOps stack
# Generates FastAPI app + Kubernetes manifests with ArgoCD, Vault, Postgres, Redis, Kafka, Grafana, Prometheus, Loki, Tempo, Kyverno

# POPRAWNE ZMIENNE - zgodne z chatgpt.sh
APP_NAME="website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgadm-chat"
ORG="exea-centrum"
NAMESPACE="davtrowebdbvault"
IMAGE="ghcr.io/${ORG}/${APP_NAME}:latest"
REPO_URL="https://github.com/${ORG}/${APP_NAME}.git"

# Aliasy dla kompatybilności
PROJECT="${APP_NAME}"
REGISTRY="${IMAGE%:*}"

ROOT_DIR="$(pwd)"
APP_DIR="app"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"

info(){ echo -e "🔧 [unified] $*"; }
mkdir_p(){ mkdir -p "$@"; }

# ==============================
# STRUKTURA KATALOGÓW
# ==============================
generate_structure(){
  info "Tworzenie struktury katalogów..."
  mkdir_p "$APP_DIR/templates" "$BASE_DIR" "$WORKFLOW_DIR"
}

# ==============================
# FASTAPI APLIKACJA
# ==============================
generate_fastapi_app(){
  info "Generowanie FastAPI aplikacji z ankietą..."
  
  cat << 'EOF' > "$APP_DIR/main.py"
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import os
import logging
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel
from typing import List, Dict, Any
import time

app = FastAPI(title="Dawid Trojanowski - Strona Osobista")
templates = Jinja2Templates(directory="templates")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi_app")

# Konfiguracja CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_CONN = os.getenv("DATABASE_URL", "dbname=appdb user=appuser password=apppass host=postgres")

Instrumentator().instrument(app).expose(app)

class SurveyResponse(BaseModel):
    question: str
    answer: str

def get_db_connection():
    """Utwórz połączenie z bazą danych z retry logic"""
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DB_CONN)
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All connection attempts failed: {e}")
                raise e

def init_database():
    """Inicjalizacja bazy danych"""
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            # Tabela odpowiedzi ankiet
            cur.execute("""
                CREATE TABLE IF NOT EXISTS survey_responses(
                    id SERIAL PRIMARY KEY,
                    question TEXT NOT NULL,
                    answer TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Tabela odwiedzin stron
            cur.execute("""
                CREATE TABLE IF NOT EXISTS page_visits(
                    id SERIAL PRIMARY KEY,
                    page VARCHAR(255) NOT NULL,
                    visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Tabela kontaktów
            cur.execute("""
                CREATE TABLE IF NOT EXISTS contact_messages(
                    id SERIAL PRIMARY KEY,
                    email VARCHAR(255) NOT NULL,
                    message TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            conn.commit()
            cur.close()
            conn.close()
            logger.info("Database initialized successfully")
            return
        except Exception as e:
            logger.warning(f"Database initialization attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All database initialization attempts failed: {e}")

@app.on_event("startup")
async def startup_event():
    init_database()

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Główna strona osobista"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("INSERT INTO page_visits (page) VALUES ('home')")
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Error logging page visit: {e}")
    
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        logger.warning(f"Health check database connection failed: {e}")
        return {"status": "healthy", "database": "disconnected", "error": str(e)}

@app.get("/api/survey/questions")
async def get_survey_questions():
    """Pobiera listę pytań do ankiety"""
    questions = [
        {
            "id": 1,
            "text": "Jak oceniasz design strony?",
            "type": "rating",
            "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
        },
        {
            "id": 2,
            "text": "Czy informacje były przydatne?",
            "type": "choice",
            "options": ["Tak", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
        },
        {
            "id": 3,
            "text": "Jakie technologie Cię zainteresowaƂy?",
            "type": "multiselect",
            "options": ["Python", "JavaScript", "React", "Kubernetes", "Docker", "PostgreSQL"]
        },
        {
            "id": 4,
            "text": "Czy poleciłbyś tę stronę innym?",
            "type": "choice",
            "options": ["Zdecydowanie tak", "Prawdopodobnie tak", "Nie wiem", "Raczej nie", "Zdecydowanie nie"]
        },
        {
            "id": 5,
            "text": "Co sądzisz o portfolio?",
            "type": "text",
            "placeholder": "Podziel się swoją opinią..."
        }
    ]
    return questions

@app.post("/api/survey/submit")
async def submit_survey(response: SurveyResponse):
    """Zapisuje odpowiedź z ankiety"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO survey_responses (question, answer) VALUES (%s, %s)",
            (response.question, response.answer)
        )
        conn.commit()
        cur.close()
        conn.close()
        logger.info(f"Survey response saved: {response.question} -> {response.answer}")
        return {"status": "success", "message": "Dziękujemy za wypełnienie ankiety!"}
    except Exception as e:
        logger.error(f"Error saving survey response: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas zapisywania odpowiedzi")

@app.get("/api/survey/stats")
async def get_survey_stats():
    """Pobiera statystyki ankiet"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT question, answer, COUNT(*) as count 
            FROM survey_responses 
            GROUP BY question, answer 
            ORDER BY question, count DESC
        """)
        responses = cur.fetchall()
        
        cur.execute("SELECT COUNT(*) FROM page_visits")
        total_visits = cur.fetchone()[0]
        
        cur.close()
        conn.close()
        
        stats = {}
        for question, answer, count in responses:
            if question not in stats:
                stats[question] = []
            stats[question].append({"answer": answer, "count": count})
        
        return {
            "survey_responses": stats,
            "total_visits": total_visits,
            "total_responses": sum(len(answers) for answers in stats.values())
        }
    except Exception as e:
        logger.error(f"Error fetching survey stats: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas pobierania statystyk")

@app.post("/api/contact")
async def submit_contact(email: str = Form(...), message: str = Form(...)):
    """Zapisuje wiadomość kontaktową"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO contact_messages (email, message) VALUES (%s, %s)",
            (email, message)
        )
        conn.commit()
        cur.close()
        conn.close()
        logger.info(f"Contact message saved from: {email}")
        return {"status": "success", "message": "Wiadomość została wysłana!"}
    except Exception as e:
        logger.error(f"Error saving contact message: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas wysyłania wiadomości")

@app.get("/api/visits")
async def get_visit_stats():
    """Pobiera statystyki odwiedzin"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT page, COUNT(*) as visits,
                   DATE(visited_at) as date
            FROM page_visits 
            GROUP BY page, DATE(visited_at)
            ORDER BY date DESC
        """)
        visits = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return {
            "visits": [
                {
                    "page": page,
                    "visits": visit_count,
                    "date": date.isoformat() if date else None
                }
                for page, visit_count, date in visits
            ]
        }
    except Exception as e:
        logger.error(f"Error fetching visit stats: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas pobierania statystyk odwiedzin")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

  cat << 'EOF' > "$APP_DIR/requirements.txt"
fastapi==0.104.1
uvicorn==0.24.0
jinja2==3.1.2
psycopg2-binary==2.9.7
prometheus-fastapi-instrumentator==5.11.1
python-multipart==0.0.6
pydantic==2.5.0
EOF
}

# ==============================
# HTML TEMPLATE (skrócony dla czytelności)
# ==============================
generate_html_template(){
  info "Generowanie szablonu HTML..."
  # Kopiuj pełny HTML z deep.sh - tutaj używam skróconej wersji
  cat << 'HTMLEOF' > "$APP_DIR/templates/index.html"
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dawid Trojanowski - Strona Osobista</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen">
    <header class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
            <h1 class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                Dawid Trojanowski
            </h1>
        </div>
    </header>
    <main class="container mx-auto px-6 py-12">
        <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
            <h2 class="text-4xl font-bold mb-6 text-purple-300">O Mnie</h2>
            <p class="text-lg text-gray-300 leading-relaxed">
                Cześć! Jestem Dawidem Trojanowskim, pasjonatem informatyki i nowych technologii.
            </p>
        </div>
    </main>
    <footer class="border-t border-purple-500/30 backdrop-blur-sm bg-black/20 mt-16">
        <div class="container mx-auto px-6 py-8 text-center text-gray-400">
            <p>Dawid Trojanowski © 2025</p>
        </div>
    </footer>
</body>
</html>
HTMLEOF
}

# ==============================
# DOCKERFILE
# ==============================
generate_dockerfile(){
  info "Generowanie Dockerfile..."
  cat << 'EOF' > "${ROOT_DIR}/Dockerfile"
FROM python:3.10-slim

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

ENV PYTHONUNBUFFERED=1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
}

# ==============================
# GITHUB ACTIONS
# ==============================
generate_github_actions(){
  info "Generowanie GitHub Actions workflow..."
  cat > "${WORKFLOW_DIR}/ci.yml" <<GHA
name: CI/CD Build & Deploy

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      
      - name: Set up Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Log in to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: \${{ github.actor }}
          password: \${{ secrets.GHCR_PAT }}
      
      - name: Build and push image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ${REGISTRY}:latest
            ${REGISTRY}:\${{ github.sha }}
          cache-from: type=registry,ref=${REGISTRY}:latest
          cache-to: type=inline
GHA
}

# ==============================
# KUBERNETES MANIFESTS
# ==============================
generate_k8s_base(){
  info "Generowanie podstawowych manifestów Kubernetes..."
  
  # ConfigMap
  cat > "${BASE_DIR}/configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
  namespace: ${NAMESPACE}
data:
  DATABASE_URL: "dbname=appdb user=appuser password=apppass host=postgres"
EOF

  # Secret
  cat > "${BASE_DIR}/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  postgres-password: "apppass"
  username: "appuser"
  password: "apppass"
EOF

  # Service Account
  cat > "${BASE_DIR}/service-account.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
imagePullSecrets:
  - name: ghcr-pull-secret
EOF

  # App Deployment
  cat > "${BASE_DIR}/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}-app
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: ${APP_NAME}
      initContainers:
      - name: wait-for-db
        image: postgres:14
        command: 
        - sh
        - -c
        - |
          echo "Waiting for database..."
          until pg_isready -h postgres -p 5432 -U appuser -d appdb; do
            echo "Database not ready. Waiting..."
            sleep 5
          done
          echo "Database ready!"
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: postgres-password
      containers:
      - name: app
        image: ${IMAGE}
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_URL
          valueFrom:
            configMapKeyRef:
              name: ${APP_NAME}-config
              key: DATABASE_URL
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 90
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 5
EOF

  # Service
  cat > "${BASE_DIR}/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-svc
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - port: 80
      targetPort: 8000
      protocol: TCP
  type: ClusterIP
EOF

  # Ingress
  cat > "${BASE_DIR}/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${APP_NAME}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}-svc
            port:
              number: 80
  - host: pgadmin.${APP_NAME}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  - host: grafana.${APP_NAME}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
EOF
}

# ==============================
# POSTGRES
# ==============================
generate_postgres(){
  info "Generowanie PostgreSQL..."
  cat > "${BASE_DIR}/postgres.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: ${NAMESPACE}
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:14
        env:
        - name: POSTGRES_DB
          value: appdb
        - name: POSTGRES_USER
          value: appuser
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: postgres-password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - exec pg_isready -U appuser -d appdb -h 127.0.0.1
          initialDelaySeconds: 30
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: ${NAMESPACE}
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
}

# ==============================
# PGADMIN
# ==============================
generate_pgadmin(){
  info "Generowanie pgAdmin..."
  cat > "${BASE_DIR}/pgadmin.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      initContainers:
      - name: wait-for-db
        image: postgres:14
        command: 
        - sh
        - -c
        - |
          until pg_isready -h postgres -p 5432 -U appuser -d appdb; do
            sleep 5
          done
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: postgres-password
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: "admin@admin.com"
        - name: PGADMIN_DEFAULT_PASSWORD
          value: "admin"
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
spec:
  selector:
    app: pgadmin
  ports:
  - port: 80
    targetPort: 80
EOF
}

# ==============================
# VAULT
# ==============================
generate_vault(){
  info "Generowanie Vault..."
  cat > "${BASE_DIR}/vault-config.yaml" <<VC
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: ${NAMESPACE}
data:
  vault.hcl: |
    storage "file" {
      path = "/vault/data"
    }
    listener "tcp" {
      address = "0.0.0.0:8200"
      tls_disable = "true"
    }
    ui = true
    disable_mlock = true
VC

  cat > "${BASE_DIR}/vault-deployment.yaml" <<VD
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:1.15.3
        args: ["server","-config=/vault/config/vault.hcl"]
        ports:
        - containerPort: 8200
        volumeMounts:
        - name: vault-config
          mountPath: /vault/config
        - name: vault-data
          mountPath: /vault/data
      volumes:
      - name: vault-config
        configMap:
          name: vault-config
  volumeClaimTemplates:
  - metadata:
      name: vault-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 8200
  selector:
    app: vault
VD
}

# ==============================
# REDIS
# ==============================
generate_redis(){
  info "Generowanie Redis..."
  cat > "${BASE_DIR}/redis.yaml" <<R
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7
        ports:
        - containerPort: 6379
        args: ["--appendonly", "yes"]
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 6379
  selector:
    app: redis
R
}

# ==============================
# KAFKA
# ==============================
generate_kafka(){
  info "Generowanie Kafka + Zookeeper..."
  cat > "${BASE_DIR}/kafka.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: zookeeper
  namespace: ${NAMESPACE}
spec:
  serviceName: zookeeper
  replicas: 1
  selector:
    matchLabels:
      app: zookeeper
  template:
    metadata:
      labels:
        app: zookeeper
    spec:
      containers:
      - name: zookeeper
        image: bitnami/zookeeper:3.9.2
        ports:
        - containerPort: 2181
        env:
        - name: ALLOW_ANONYMOUS_LOGIN
          value: "yes"
---
apiVersion: v1
kind: Service
metadata:
  name: zookeeper
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 2181
  selector:
    app: zookeeper
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  serviceName: kafka
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.8.0
        env:
        - name: KAFKA_CFG_ZOOKEEPER_CONNECT
          value: zookeeper:2181
        - name: ALLOW_PLAINTEXT_LISTENER
          value: "yes"
        ports:
        - containerPort: 9092
        volumeMounts:
        - name: kafka-data
          mountPath: /bitnami/kafka
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 9092
  selector:
    app: kafka
EOF
}

# ==============================
# PROMETHEUS
# ==============================
generate_prometheus(){
  info "Generowanie Prometheus..."
  cat > "${BASE_DIR}/prometheus-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'fastapi'
        metrics_path: /metrics
        static_configs:
          - targets: ['${APP_NAME}-svc:80']
EOF

  cat > "${BASE_DIR}/prometheus-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        args: ["--config.file=/etc/prometheus/prometheus.yml"]
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 9090
  selector:
    app: prometheus
EOF
}

# ==============================
# GRAFANA
# ==============================
generate_grafana(){
  info "Generowanie Grafana..."
  cat > "${BASE_DIR}/grafana-secret.yaml" <<GS
apiVersion: v1
kind: Secret
metadata:
  name: grafana-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  admin-user: admin
  admin-password: admin
GS

  cat > "${BASE_DIR}/grafana-deployment.yaml" <<GD
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_USER
          valueFrom:
            secretKeyRef:
              name: grafana-secret
              key: admin-user
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-secret
              key: admin-password
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 3000
  selector:
    app: grafana
GD
}

# ==============================
# LOKI
# ==============================
generate_loki(){
  info "Generowanie Loki..."
  cat > "${BASE_DIR}/loki-config.yaml" <<LKC
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      path_prefix: /tmp/loki
      storage:
        filesystem:
          chunks_directory: /tmp/loki/chunks
          rules_directory: /tmp/loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
LKC

  cat > "${BASE_DIR}/loki-deployment.yaml" <<LKD
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.0
        args:
          - -config.file=/etc/loki/loki.yaml
        ports:
        - containerPort: 3100
        volumeMounts:
        - name: config
          mountPath: /etc/loki
      volumes:
      - name: config
        configMap:
          name: loki-config
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 3100
  selector:
    app: loki
LKD
}

# ==============================
# PROMTAIL
# ==============================
generate_promtail(){
  info "Generowanie Promtail..."
  cat > "${BASE_DIR}/promtail-config.yaml" <<PTC
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: ${NAMESPACE}
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    positions:
      filename: /tmp/positions.yaml
    clients:
      - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
    - job_name: system
      static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
PTC

  cat > "${BASE_DIR}/promtail-deployment.yaml" <<PTD
apiVersion: apps/v1
kind: Deployment
metadata:
  name: promtail
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      containers:
      - name: promtail
        image: grafana/promtail:2.9.0
        args:
          - -config.file=/etc/promtail/promtail.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: varlog
        hostPath:
          path: /var/log
PTD
}

# ==============================
# TEMPO
# ==============================
generate_tempo(){
  info "Generowanie Tempo..."
  cat > "${BASE_DIR}/tempo-config.yaml" <<TC
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    distributor:
      receivers:
        otlp:
          protocols:
            http:
            grpc:
    storage:
      trace:
        backend: local
        local:
          path: /var/tempo/traces
TC

  cat > "${BASE_DIR}/tempo-deployment.yaml" <<TD
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.5.0
        args:
          - -config.file=/etc/tempo/tempo.yaml
        ports:
        - containerPort: 3200
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: data
          mountPath: /var/tempo
      volumes:
      - name: config
        configMap:
          name: tempo-config
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 3200
  selector:
    app: tempo
TD
}

# ==============================
# KYVERNO POLICY
# ==============================
generate_kyverno(){
  info "Generowanie Kyverno Policy..."
  cat > "${BASE_DIR}/kyverno-policy.yaml" <<KY
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Labels 'app' and 'environment' are required."
      pattern:
        metadata:
          labels:
            app: "?*"
            environment: "?*"
KY
}

# ==============================
# ARGOCD APPLICATION
# ==============================
generate_argocd_app(){
  info "Generowanie ArgoCD Application..."
  cat > "${BASE_DIR}/argocd-app.yaml" <<'AA'
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
    repoURL: https://github.com/exea-centrum/website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.git
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: davtrowebdb
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
AA
}

# ==============================
# STANDALONE ARGOCD APP (do apply z CLI)
# ==============================
generate_argocd_standalone(){
  info "Generowanie standalone ArgoCD Application (poza kustomization)..."
  cat > "${ROOT_DIR}/argocd-application.yaml" <<'STANDALONE'
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
    repoURL: https://github.com/exea-centrum/website-db-argocd-kustomize-kyverno-grafana-loki-tempo-pgadmin.git
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: davtrowebdb
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
STANDALONE
}

# ==============================
# KUSTOMIZATION
# ==============================
generate_kustomization(){
  info "Generowanie kustomization.yaml..."
  cat > "${BASE_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

resources:
  - service-account.yaml
  - configmap.yaml
  - secret.yaml
  - vault-config.yaml
  - vault-deployment.yaml
  - postgres.yaml
  - pgadmin.yaml
  - redis.yaml
  - kafka.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - prometheus-config.yaml
  - prometheus-deployment.yaml
  - grafana-secret.yaml
  - grafana-deployment.yaml
  - loki-config.yaml
  - loki-deployment.yaml
  - promtail-config.yaml
  - promtail-deployment.yaml
  - tempo-config.yaml
  - tempo-deployment.yaml
  - kyverno-policy.yaml

commonLabels:
  app: ${APP_NAME}
  environment: development
  managed-by: argocd

images:
  - name: ${REGISTRY}
    newTag: latest
EOF
}

# ==============================
# README
# ==============================
generate_readme(){
  info "Generowanie README.md..."
  cat > "${ROOT_DIR}/README.md" <<MD
# ${PROJECT} - Unified GitOps Stack

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
\`\`\`bash
chmod +x unified-deployment.sh
./unified-deployment.sh generate
\`\`\`

### 2. Inicjalizacja i push do GitHub
\`\`\`bash
git init
git add .
git commit -m "Initial commit - unified stack"
git branch -M main
git remote add origin ${REPO_URL}
git push -u origin main
\`\`\`

### 3. Weryfikacja lokalnie (opcjonalnie)
\`\`\`bash
# Sprawdź czy Kustomize działa
kubectl kustomize manifests/base

# Sprawdź strukturę
tree manifests/
\`\`\`

### 4. Deploy z ArgoCD
\`\`\`bash
# Upewnij się że ArgoCD jest zainstalowany
kubectl get namespace argocd

# Zastosuj Application manifest
kubectl apply -f argocd-application.yaml

# Sprawdź status
kubectl get applications -n argocd
kubectl describe application website-db-stack -n argocd

# Zobacz logi sync
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
\`\`\`

### 5. Debug jeśli są problemy
\`\`\`bash
# Sprawdź czy repo jest dostępne dla ArgoCD
argocd repo list

# Dodaj repo jeśli nie ma
argocd repo add ${REPO_URL}

# Sprawdź czy manifesty są poprawne
kubectl kustomize manifests/base | kubectl apply --dry-run=client -f -
\`\`\`

## ⚠️ Typowe problemy

### "app path does not exist"
**Przyczyna**: Manifesty nie zostały jeszcze wypushowane do repo lub ścieżka jest błędna.

**Rozwiązanie**:
1. Upewnij się że zrobiłeś `git push` po generowaniu
2. Sprawdź czy folder `manifests/base/` istnieje w repo na GitHub
3. Sprawdź czy plik `manifests/base/kustomization.yaml` jest dostępny

### "Unable to generate manifests"
**Przyczyna**: Błąd w kustomization.yaml lub brakujący plik.

**Rozwiązanie**:
\`\`\`bash
# Test lokalny
kubectl kustomize manifests/base

# Sprawdź czy wszystkie pliki istnieją
ls -la manifests/base/
\`\`\`

### ArgoCD nie widzi repo
**Rozwiązanie**:
\`\`\`bash
# Dodaj credentials dla prywatnego repo
kubectl create secret generic repo-creds \\
  --from-literal=url=${REPO_URL} \\
  --from-literal=password=YOUR_GITHUB_TOKEN \\
  --from-literal=username=YOUR_GITHUB_USERNAME \\
  -n argocd
\`\`\`

## 🌐 Dostęp

- **Aplikacja**: http://${PROJECT}.local
- **pgAdmin**: http://pgadmin.${PROJECT}.local (admin@admin.com / admin)
- **Grafana**: http://grafana.${PROJECT}.local (admin / admin)
- **Vault**: http://vault.${PROJECT}.local:8200

## 📊 Baza danych

### Tabele:
- \`survey_responses\` - Odpowiedzi z ankiety
- \`page_visits\` - Statystyki odwiedzin
- \`contact_messages\` - Wiadomości kontaktowe

## 🔐 Sekretna konfiguracja

### GitHub Secrets wymagane:
- \`GHCR_PAT\` - Personal Access Token dla GitHub Container Registry

## 📦 Namespace
\`${NAMESPACE}\`

## 🏗️ Architektura

\`\`\`
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
\`\`\`

## 🛠️ Rozwój

### Struktura projektu:
\`\`\`
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
\`\`\`

## 📝 Licencja

MIT License - Dawid Trojanowski © 2025
MD
}

# ==============================
# GŁÓWNA FUNKCJA
# ==============================
generate_all(){
  info "🚀 Rozpoczynam generowanie unified stack..."
  echo ""
  
  generate_structure
  generate_fastapi_app
  generate_html_template
  generate_dockerfile
  generate_github_actions
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
  generate_kyverno
  generate_argocd_app
  generate_argocd_standalone
  generate_kustomization
  generate_readme
  
  echo ""
  info "✅ WSZYSTKO GOTOWE!"
  echo ""
  echo "📦 Wygenerowano:"
  echo "   ✓ FastAPI aplikacja w app/"
  echo "   ✓ Dockerfile"
  echo "   ✓ GitHub Actions workflow"
  echo "   ✓ Kubernetes manifesty w manifests/base/"
  echo "   ✓ argocd-application.yaml (standalone w root)"
  echo "   ✓ README.md"
  echo ""
  echo "🎯 Komponenty:"
  echo "   ✓ FastAPI + PostgreSQL + pgAdmin"
  echo "   ✓ Vault (secrets management)"
  echo "   ✓ Redis (cache)"
  echo "   ✓ Kafka + Zookeeper (messaging)"
  echo "   ✓ Prometheus + Grafana (monitoring)"
  echo "   ✓ Loki + Promtail (logging)"
  echo "   ✓ Tempo (tracing)"
  echo "   ✓ ArgoCD (GitOps)"
  echo "   ✓ Kyverno (policies)"
  echo ""
  echo "🚀 Następne kroki:"
  echo ""
  echo "1️⃣ Inicjalizacja Git i push:"
  echo "   git init"
  echo "   git add ."
  echo "   git commit -m 'Initial commit - unified stack'"
  echo "   git branch -M main"
  echo "   git remote add origin ${REPO_URL}"
  echo "   git push -u origin main"
  echo ""
  echo "2️⃣ Weryfikacja struktury:"
  echo "   tree manifests/"
  echo ""
  echo "3️⃣ Test lokalny Kustomize:"
  echo "   kubectl kustomize manifests/base"
  echo ""
  echo "4️⃣ Deploy ArgoCD Application (po push do repo):"
  echo "   kubectl apply -f argocd-application.yaml"
  echo ""
  echo "5️⃣ Sprawdź status w ArgoCD:"
  echo "   kubectl get applications -n argocd"
  echo "   kubectl describe application website-db-stack -n argocd"
  echo ""
  echo "⚠️  WAŻNE: Upewnij się że:"
  echo "   ✓ Repozytorium ${REPO_URL} istnieje"
  echo "   ✓ ArgoCD jest zainstalowany (kubectl get ns argocd)"
  echo "   ✓ Folder manifests/base/ zawiera wszystkie pliki"
  echo ""
  echo "🌐 Dostęp:"
  echo "   App: http://${APP_NAME}.local"
  echo "   pgAdmin: http://pgadmin.${APP_NAME}.local"
  echo "   Grafana: http://grafana.${APP_NAME}.local"
  echo ""
}

# ==============================
# MENU
# ==============================
case "${1:-}" in
  generate)
    generate_all
    ;;
  help|-h|--help)
    echo "Unified Deployment Script"
    echo ""
    echo "Usage: $0 generate"
    echo ""
    echo "Generuje kompletny stack z aplikacją FastAPI i infrastrukturą Kubernetes"
    ;;
  *)
    echo "❌ Nieprawidłowa komenda"
    echo "Użyj: $0 generate"
    echo "Lub: $0 help"
    exit 1
    ;;
esac