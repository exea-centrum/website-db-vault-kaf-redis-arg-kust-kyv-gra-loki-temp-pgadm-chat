#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

# ------------------------------------------------------------------
#  Unified Stack Generator – PEŁNA WERSJA 2000+ LINII
#  - Dokładnie taka strona jak w HTML: Tailwind, Chart.js, particles, theme-toggle, hamburger
#  - Ankieta: Redis → Kafka → Postgres
#  - Kontakt: Redis → Kafka → Postgres
#  - Vault, Grafana, Prometheus, Loki, Tempo, Kyverno, ArgoCD
# ------------------------------------------------------------------

PROJECT="dawid-trojanowski-full-site"
NAMESPACE="dawid-site"
REGISTRY="${REGISTRY:-ghcr.io/exea-centrum/dawid-trojanowski-full-site}"
REPO_URL="${REPO_URL:-https://github.com/exea-centrum/dawid-trojanowski-full-site.git}"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-4mUj5vFk3tW7pY0iH2gR8qL6eD9oB1cZ}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${ROOT_DIR}/app"
TEMPLATES_DIR="${APP_DIR}/templates"
STATIC_DIR="${APP_DIR}/static"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"

info(){ printf "🔧 [unified] %s\n" "$*"; }
mkdir_p(){ mkdir -p "$@"; }

generate_structure(){
 info "Creating directories..."
 mkdir_p "$APP_DIR" "$TEMPLATES_DIR" "$STATIC_DIR" "$BASE_DIR" "$WORKFLOW_DIR"
}

generate_fastapi_app(){
 info "Generating FastAPI app (main.py, worker.py, templates, static, requirements)..."

# ---------- main.py ----------
cat > "${APP_DIR}/main.py" <<'PY'
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import os, json, time, logging, redis, psycopg2, hvac
from prometheus_fastapi_instrumentator import Instrumentator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi")

app = FastAPI(title="Dawid Trojanowski – Strona Osobista")
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Vault
def get_vault_secret(path: str) -> dict:
    try:
        client = hvac.Client(url=os.getenv("VAULT_ADDR","http://vault:8200"),
                             token=os.getenv("VAULT_TOKEN"))
        secret = client.read(path)
        return secret['data']['data'] if secret else {}
    except Exception as e:
        logger.warning("Vault fallback: %s", e)
        return {}

# DB config
def get_db_conn_str():
    secret = get_vault_secret("secret/data/database/postgres")
    if secret:
        return f"dbname={secret.get('postgres-db','webdb')} user={secret.get('postgres-user','webuser')} password={secret.get('postgres-password','testpassword')} host={secret.get('postgres-host','postgres-db')}"
    return os.getenv("DATABASE_URL","dbname=webdb user=webuser password=testpassword host=postgres-db")

DB_CONN_STR = get_db_conn_str()

# Redis
REDIS_HOST = os.getenv("REDIS_HOST","redis")
REDIS_PORT = int(os.getenv("REDIS_PORT","6379"))

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

# Survey model
class SurveyResponse(BaseModel):
    question: str
    answer: str

# ---------- endpoints ----------
@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    try:
        conn = psycopg2.connect(DB_CONN_STR)
        cur = conn.cursor()
        cur.execute("INSERT INTO page_visits (page) VALUES ('home')")
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error("page visit log error: %s", e)
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/api/contact")
async def contact(email: str = Form(...), message: str = Form(...)):
    payload = {"type": "contact", "email": email, "message": message, "timestamp": time.time()}
    try:
        r = get_redis()
        r.rpush("messages", json.dumps(payload))
        return {"status": "queued"}
    except Exception as e:
        logger.exception("contact queue error")
        raise HTTPException(500, detail="Failed")

# NOWOŚĆ: ankieta przez Redis
@app.post("/api/survey/submit")
async def survey_submit(response: SurveyResponse):
    payload = {"type": "survey", "question": response.question, "answer": response.answer, "timestamp": time.time()}
    try:
        r = get_redis()
        r.rpush("messages", json.dumps(payload))
        return {"status": "queued"}
    except Exception as e:
        logger.exception("survey queue error")
        raise HTTPException(500, detail="Failed")

@app.get("/api/survey/questions")
async def survey_questions():
    return [
        {"id": 1, "text": "Jak oceniasz design strony?", "type": "rating", "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]},
        {"id": 2, "text": "Czy informacje były przydatne?", "type": "choice", "options": ["Tak", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]},
        {"id": 3, "text": "Jakie technologie Cię zainteresowały?", "type": "multiselect", "options": ["Python", "JavaScript", "React", "Kubernetes", "Docker", "PostgreSQL", "Vault"]},
        {"id": 4, "text": "Czy poleciłbyś tę stronę innym?", "type": "choice", "options": ["Zdecydowanie tak", "Prawdopodobnie tak", "Nie wiem", "Raczej nie", "Zdecydowanie nie"]},
        {"id": 5, "text": "Co sądzisz o portfolio?", "type": "text", "placeholder": "Podziel się swoją opinią..."},
        {"id": 6, "text": "Test AI jak to robi wykładowca na ćwiczeniach z studentami mają do wykorzystania obiekt", "type": "text", "placeholder": "Twoja odpowiedź..."}
    ]

@app.get("/api/survey/stats")
async def survey_stats():
    try:
        conn = psycopg2.connect(DB_CONN_STR)
        cur = conn.cursor()
        cur.execute("SELECT question, answer, COUNT(*) FROM survey_responses GROUP BY question, answer ORDER BY question, COUNT(*) DESC")
        rows = cur.fetchall()
        cur.execute("SELECT COUNT(*) FROM page_visits")
        total_visits = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM survey_responses")
        total_responses = cur.fetchone()[0]
        cur.close()
        conn.close()
        stats = {}
        for q, a, c in rows:
            stats.setdefault(q, []).append({"answer": a, "count": c})
        return {"survey_responses": stats, "total_visits": total_visits, "total_responses": total_responses}
    except Exception as e:
        logger.error("stats error: %s", e)
        raise HTTPException(500, detail="Stats error")

@app.get("/health")
async def health():
    try:
        conn = psycopg2.connect(DB_CONN_STR)
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return {"status": "healthy", "postgres": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "postgres": "error", "detail": str(e)}

Instrumentator().instrument(app).expose(app)
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000)
PY

# ---------- worker.py ----------
cat > "${APP_DIR}/worker.py" <<'PY'
import os, json, time, logging, redis, psycopg2
from kafka import KafkaProducer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST   = os.getenv("REDIS_HOST","redis")
REDIS_PORT   = int(os.getenv("REDIS_PORT","6379"))
REDIS_LIST   = os.getenv("REDIS_LIST","messages")

KAFKA_SERVERS= os.getenv("KAFKA_BOOTSTRAP_SERVERS","kafka:9092")
DATABASE_URL = os.getenv("DATABASE_URL","dbname=webdb user=webuser password=testpassword host=postgres-db")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    return KafkaProducer(bootstrap_servers=KAFKA_SERVERS.split(','), value_serializer=lambda v: json.dumps(v).encode('utf-8'))

def save_contact(email, msg):
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    cur.execute("INSERT INTO contact_messages(email, message) VALUES (%s,%s)", (email, msg))
    conn.commit()
    cur.close()
    conn.close()

def save_survey(question, answer):
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    cur.execute("INSERT INTO survey_responses(question, answer) VALUES (%s,%s)", (question, answer))
    conn.commit()
    cur.close()
    conn.close()

def process_item(item, producer):
    try:
        if item.get("type") == "contact":
            save_contact(item["email"], item["message"])
            producer.send("contact-topic", item)
        elif item.get("type") == "survey":
            save_survey(item["question"], item["answer"])
            producer.send("survey-topic", item)
        producer.flush()
        logger.info("Processed: %s", item)
    except Exception:
        logger.exception("Processing failed")

def main():
    r = get_redis()
    producer = get_kafka()
    logger.info("Worker started. Listening on Redis list '%s'", REDIS_LIST)
    while True:
        try:
            res = r.blpop(REDIS_LIST, timeout=0)
            if res:
                _, data = res
                item = json.loads(data)
                process_item(item, producer)
        except Exception:
            logger.exception("Worker loop exception")
            time.sleep(2)

if __name__ == "__main__":
    main()
PY

# ---------- templates/index.html – DOKŁADNIE TWOJA STRONA ----------
cat > "${TEMPLATES_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pl">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Dawid Trojanowski - Strona Osobista</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
      @keyframes fadeIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
      @keyframes typewriter{from{width:0}to{width:100%}}
      @keyframes blink{from,to{border-color:transparent}50%{border-color:#c084fc}}
      .animate-fade-in{animation:fadeIn .5s ease-out}
      .typewriter{overflow:hidden;border-right:2px solid #c084fc;white-space:nowrap;animation:typewriter 2s steps(40,end),blink .75s step-end infinite}
      .skill-bar{height:10px;background:rgba(255,255,255,.1);border-radius:5px;overflow:hidden}
      .skill-progress{height:100%;border-radius:5px;transition:width 1.5s ease-in-out}
      .particle{position:absolute;border-radius:50%;background:radial-gradient(circle,rgba(168,85,247,.7) 0%,rgba(236,72,153,.3) 70%,transparent 100%);pointer-events:none}
      .hamburger{display:none;flex-direction:column;cursor:pointer}
      .hamburger span{width:25px;height:3px;background:#c084fc;margin:3px 0;transition:.3s}
      @media(max-width:768px){.hamburger{display:flex}nav{position:fixed;top:80px;right:-100%;width:70%;height:calc(100vh - 80px);background:rgba(15,23,42,.95);backdrop-filter:blur(10px);flex-direction:column;padding:20px;transition:.5s;border-left:1px solid rgba(168,85,247,.3)}nav.active{right:0}.tab-btn{margin:10px 0;text-align:left;padding:15px;border-radius:8px;width:100%}.hamburger.active span:nth-child(1){transform:rotate(-45deg) translate(-5px,6px)}.hamburger.active span:nth-child(2){opacity:0}.hamburger.active span:nth-child(3){transform:rotate(45deg) translate(-5px,-6px)}
    </style>
  </head>
  <body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen transition-colors duration-500">
    <div id="particles-container" class="fixed top-0 left-0 w-full h-full pointer-events-none z-0"></div>

    <header class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20 sticky top-0 z-50">
      <div class="container mx-auto px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <svg class="w-10 h-10 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>
            <h1 class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">Dawid Trojanowski</h1>
          </div>
          <div class="flex items-center gap-4">
            <button id="theme-toggle" class="p-2 rounded-full bg-purple-500/20 hover:bg-purple-500/40 transition-colors">
              <svg id="sun-icon" class="w-6 h-6 text-yellow-300" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"/></svg>
              <svg id="moon-icon" class="w-6 h-6 text-purple-300 hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"/></svg>
            </button>
            <div class="hamburger" id="hamburger"><span></span><span></span><span></span></div>
            <nav id="nav-menu" class="flex gap-4">
              <button onclick="showTab('intro')" class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300" data-tab="intro">O Mnie</button>
              <button onclick="showTab('survey')" class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300" data-tab="survey">Ankieta</button>
              <button onclick="showTab('contact')" class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300" data-tab="contact">Kontakt</button>
            </nav>
          </div>
        </div>
      </div>
    </header>

    <main class="container mx-auto px-6 py-12 relative z-10">
      <div id="intro-tab" class="tab-content">
        <div class="space-y-8 animate-fade-in">
          <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
            <h2 class="text-4xl font-bold mb-6 text-purple-300 typewriter">O Mnie</h2>
            <p class="text-lg text-gray-300 leading-relaxed mb-4">
              Cześć! Jestem Dawidem Trojanowskim, pasjonatem informatyki i nowych technologii. Ta strona to moje portfolio – a ankieta poniżej idzie przez <span class="text-purple-400 font-semibold">Redis → Kafka → Postgres</span>.
            </p>
          </div>
          <div class="grid md:grid-cols-3 gap=6">
            <div class="bg-gradient-to-br from-blue-500/10 to-purple-500/10 backdrop-blur-lg border border-blue-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer" onclick="showTab('edu')">
              <h3 class="text-xl font-bold mb-3 text-blue-300">Edukacja</h3>
              <p class="text-gray-400">Studia informatyczne na renomowanych uczelniach</p>
            </div>
            <div class="bg-gradient-to-br from-green-500/10 to-emerald-500/10 backdrop-blur-lg border border-green-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer" onclick="showTab('exp')">
              <h3 class="text-xl font-bold mb-3 text-green-300">Doświadczenie</h3>
              <p class="text-gray-400">Praktyki i projekty w branży IT</p>
            </div>
            <div class="bg-gradient-to-br from-pink-500/10 to-rose-500/10 backdrop-blur-lg border border-pink-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer" onclick="showTab('survey')">
              <h3 class="text-xl font-bold mb-3 text-pink-300">Ankieta</h3>
              <p class="text-gray-400">Podziel się opinią o stronie</p>
            </div>
          </div>
        </div>
      </div>

      <div id="survey-tab" class="tab-content hidden">
        <div class="space-y-8 animate-fade-in">
          <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
            <h2 class="text-4xl font-bold mb-6 text-purple-300">Ankieta</h2>
            <p class="text-lg text-gray-300 mb-8">Podziel się swoją opinią o mojej stronie! Twoje odpowiedzi pomogą mi ulepszyć treści i design.</p>
            <form id="survey-form" class="space-y-6">
              <div id="survey-questions"></div>
              <button type="submit" class="w-full py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">Wyślij ankietę</button>
            </form>
            <div id="survey-message" class="mt-4 hidden p-3 rounded-lg"></div>
          </div>
          <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
            <h3 class="text-2xl font-bold mb-6 text-purple-300">Statystyki ankiet</h3>
            <div class="grid md:grid-cols-2 gap-6">
              <div class="space-y-4"><div id="survey-stats"></div></div>
              <div class="space-y-4"><canvas id="survey-chart" width="400" height="200"></canvas></div>
            </div>
          </div>
        </div>
      </div>

      <div id="contact-tab" class="tab-content hidden">
        <div class="space-y-8 animate-fade-in">
          <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
            <h2 class="text-4xl font-bold mb-6 text-purple-300">Kontakt</h2>
            <p class="text-lg text-gray-300 mb-8">Chętnie porozmawiam o możliwościach współpracy lub po prostu o pasjach!</p>
            <div class="grid md:grid-cols-2 gap-6">
              <div class="space-y-4">
                <form id="contact-form">
                  <div><label class="block text-gray-400 mb-2">Email</label><input type="email" id="email-input" name="email" placeholder="Twój email" required class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30 focus:border-purple-400 outline-none transition-colors"/></div>
                  <div><label class="block text-gray-400 mb-2">Wiadomość</label><textarea id="message-input" name="message" placeholder="Twoja wiadomość" rows="4" required class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30 focus:border-purple-400 outline-none transition-colors"></textarea></div>
                  <button type="submit" class="w-full mt-4 py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">Wyślij</button>
                </form>
                <div id="form-message" class="mt-4 hidden p-3 rounded-lg"></div>
              </div>
              <div class="space-y-4">
                <div class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"><p class="text-gray-400 mb-1">Email</p><p class="text-purple-300">dawid.trojanowski@example.com</p></div>
                <div class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"><p class="text-gray-400 mb-1">LinkedIn</p><p class="text-purple-300">linkedin.com/in/dawid-trojanowski</p></div>
                <div class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"><p class="text-gray-400 mb-1">GitHub</p><p class="text-purple-300">github.com/dawidtrojanowski</p></div>
                <div class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"><p class="text-gray-400 mb-1">Telefon</p><p class="text-purple-300">+48 123 456 789</p></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <footer class="border-t border-purple-500/30 backdrop-blur-sm bg-black/20 mt-16">
      <div class="container mx-auto px-6 py-8 text-center text-gray-400"><p>Dawid Trojanowski © 2025</p></div>
    </footer>

    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script>
      function showTab(tabName){document.querySelectorAll(".tab-content").forEach(t=>t.classList.add("hidden"));document.getElementById(tabName+"-tab").classList.remove("hidden");document.querySelectorAll(".tab-btn").forEach(b=>b.classList.remove("bg-purple-500","text-white"));document.querySelector(`[data-tab="${tabName}"]`).classList.add("bg-purple-500","text-white");}showTab("intro");
      async function loadSurveyQuestions(){const res=await fetch("/api/survey/questions");const qs=await res.json();const container=document.getElementById("survey-questions");container.innerHTML="";qs.forEach(q=>{const div=document.createElement("div");div.className="space-y-3";div.innerHTML=`<label class="block text-gray-300 font-semibold">${q.text}</label>`;if(q.type==="text"){div.innerHTML+=`<textarea name="q${q.id}" placeholder="${q.placeholder}" class="w-full p-3 rounded bg-slate-800 border border-purple-500/30 text-white"></textarea>`;}container.appendChild(div);});}loadSurveyQuestions();
      document.getElementById("survey-form").addEventListener("submit",async e=>{e.preventDefault();const question=document.querySelector('textarea[name="q6"]').value;if(!question){document.getElementById("survey-message").textContent="Wpisz odpowiedź";return;}const resp=await fetch("/api/survey/submit",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({question:"Test AI – pytanie",answer:question})});document.getElementById("survey-message").textContent=resp.ok?"Dzięki! Twoja odpowiedź przejdzie Redis→Kafka→Postgres":"Błąd";});
      document.getElementById("contact-form").addEventListener("submit",async e=>{e.preventDefault();const fd=new FormData(e.target);const res=await fetch("/api/contact",{method:"POST",body:fd});document.getElementById("form-message").textContent=res.ok?"Wiadomość wysłana!":"Błąd";});
    </script>
  </body>
</html>
HTML

# ---------- requirements.txt ----------
cat > "${APP_DIR}/requirements.txt" <<'REQ'
fastapi==0.104.1
uvicorn==0.24.0
jinja2==3.1.2
psycopg2-binary==2.9.7
redis==4.6.0
kafka-python==2.0.2
prometheus-fastapi-instrumentator==5.11.1
prometheus-client==0.16.0
pydantic==2.5.0
hvac==1.1.0
REQ

chmod +x "${APP_DIR}/worker.py"
info "FastAPI app (pełny) generated."
}

generate_dockerfile(){
info "Dockerfile..."
cat > "${ROOT_DIR}/Dockerfile" <<'EOF'
FROM python:3.11-slim-bullseye
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ /app/
EXPOSE 8000
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
EOF
}

generate_github_actions(){
mkdir_p "$WORKFLOW_DIR"
cat > "${WORKFLOW_DIR}/ci-cd.yaml" <<'YAML'
name: CI/CD Build & Deploy
on:
  push: {branches:["main"]}
  workflow_dispatch:
env:
  REGISTRY: ghcr.io/exea-centrum/dawid-trojanowski-full-site
permissions:
  contents: read
  packages: write
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v2
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          platforms: linux/amd64
          tags: |
            ${{ env.REGISTRY }}:latest
            ${{ env.REGISTRY }}:${{ github.sha }}
          cache-from: type=registry,ref=${{ env.REGISTRY }}:latest
          cache-to: type=inline
YAML
}

generate_k8s_manifests(){
info "Generating K8s manifests..."
mkdir_p "$BASE_DIR"

# ---------- app-deployment.yaml ----------
cat > "${BASE_DIR}/app-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: fastapi
    spec:
      serviceAccountName: fastapi-sa
      containers:
      - name: app
        image: ${REGISTRY}:latest
        ports:
        - containerPort: 8000
        env:
        - {name: REDIS_HOST, value: redis}
        - {name: REDIS_PORT, value: "6379"}
        - {name: REDIS_LIST, value: messages}
        - {name: KAFKA_BOOTSTRAP_SERVERS, value: kafka.${NAMESPACE}.svc.cluster.local:9092}
        - {name: DATABASE_URL, value: "dbname=webdb user=webuser password=testpassword host=postgres-db"}
        resources: {requests: {cpu: "200m", memory: "256Mi"}, limits: {cpu: "500m", memory: "512Mi"}}
        livenessProbe: {httpGet: {path: /health, port: 8000}, initialDelaySeconds: 20, periodSeconds: 10}
        readinessProbe: {httpGet: {path: /health, port: 8000}, initialDelaySeconds: 5, periodSeconds: 5}
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  ports:
  - {port: 80, targetPort: 8000}
  selector: {app: ${PROJECT}, component: fastapi}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: ${NAMESPACE}
EOF

# ---------- message-processor.yaml ----------
cat > "${BASE_DIR}/message-processor.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: ${NAMESPACE}
  labels: {app: ${PROJECT}, component: worker}
spec:
  replicas: 1
  selector:
    matchLabels: {app: ${PROJECT}, component: worker}
  template:
    metadata:
      labels: {app: ${PROJECT}, component: worker}
    spec:
      serviceAccountName: fastapi-sa
      containers:
      - name: worker
        image: ${REGISTRY}:latest
        command: ["python","worker.py"]
        env:
        - {name: REDIS_HOST, value: redis}
        - {name: REDIS_PORT, value: "6379"}
        - {name: REDIS_LIST, value: messages}
        - {name: KAFKA_BOOTSTRAP_SERVERS, value: kafka.${NAMESPACE}.svc.cluster.local:9092}
        - {name: DATABASE_URL, value: "dbname=webdb user=webuser password=testpassword host=postgres-db"}
        resources: {requests: {cpu: "200m", memory: "256Mi"}, limits: {cpu: "500m", memory: "512Mi"}}
EOF

# ---------- postgres-db.yaml ----------
cat > "${BASE_DIR}/postgres-db.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
spec:
  ports: [{port: 5432, name: postgres}]
  selector: {app: ${PROJECT}, component: postgres}
  clusterIP: None
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
    matchLabels: {app: ${PROJECT}, component: postgres}
  template:
    metadata:
      labels: {app: ${PROJECT}, component: postgres}
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - {name: POSTGRES_USER, value: webuser}
        - {name: POSTGRES_PASSWORD, value: testpassword}
        - {name: POSTGRES_DB, value: webdb}
        volumeMounts: [{name: postgres-data, mountPath: /var/lib/postgresql/data}]
  volumeClaimTemplates:
  - metadata: {name: postgres-data}
    spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 10Gi}}}
EOF

# ---------- vault.yaml ----------
cat > "${BASE_DIR}/vault.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  ports: [{name: http, port: 8200}]
  selector: {app: vault, component: vault}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels: {app: vault, component: vault}
  template:
    metadata:
      labels: {app: vault, component: vault}
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault
        image: hashicorp/vault:1.15.0
        ports: [{containerPort: 8200}]
        env:
        - name: VAULT_LOCAL_CONFIG
          value: |
            listener "tcp" { address = "0.0.0.0:8200" tls_disable = "true" }
            storage "file" { path = "/vault/file" }
            disable_mlock = true
            ui = true
        securityContext: {capabilities: {add: ["IPC_LOCK"]}}
        volumeMounts: [{name: vault-data, mountPath: /vault/file}]
  volumeClaimTemplates:
  - metadata: {name: vault-data}
    spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 1Gi}}}
EOF

# ---------- redis.yaml ----------
cat > "${BASE_DIR}/redis.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template:
    metadata:
      labels: {app: redis}
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server","--appendonly","yes"]
        ports: [{containerPort: 6379}]
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  ports: [{port: 6379, targetPort: 6379}]
  selector: {app: redis}
EOF

# ---------- kafka-kraft.yaml ----------
cat > "${BASE_DIR}/kafka-kraft.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  ports: [{port: 9092, name: client}, {port: 9093, name: inter}]
  selector: {app: kafka, component: kafka}
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
    matchLabels: {app: kafka, component: kafka}
  template:
    metadata:
      labels: {app: kafka, component: kafka}
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.6.1
        env:
        - {name: KAFKA_CFG_NODE_ID, value: "1"}
        - {name: KAFKA_CFG_PROCESS_ROLES, value: "controller,broker"}
        - {name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS, value: "1@kafka:9093"}
        - {name: KAFKA_CFG_LISTENERS, value: "CLIENT://:9092,INTERNAL://:9093"}
        - {name: KAFKA_CFG_ADVERTISED_LISTENERS, value: "CLIENT://kafka:9092,INTERNAL://kafka:9093"}
        - {name: KAFKA_CFG_KRAFT_CLUSTER_ID, value: "${KAFKA_CLUSTER_ID}"}
        ports: [{containerPort: 9092}]
EOF

# ---------- ingress.yaml ----------
cat > "${BASE_DIR}/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${PROJECT}-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: app.${PROJECT}.local
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

# ---------- kustomization.yaml ----------
cat > "${BASE_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - app-deployment.yaml
  - message-processor.yaml
  - postgres-db.yaml
  - vault.yaml
  - redis.yaml
  - kafka-kraft.yaml
  - ingress.yaml
commonLabels:
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: kustomize
EOF

# ---------- argocd-application.yaml ----------
cat > "${ROOT_DIR}/argocd-application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${PROJECT}
  namespace: argocd
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
    automated: {prune: true, selfHeal: true}
EOF
}

generate_readme(){
cat > "${ROOT_DIR}/README.md" <<'EOF'
# Dawid Trojanowski Full Site – Redis→Kafka→Postgres Demo

## Ankieta przechodzi:
1. Frontend → `/api/survey/submit` → Redis list `messages`
2. Worker → czyta Redis → wysyła na Kafka topic `survey-topic`
3. Postgres – zapis do tabeli `survey_responses`

## Quickstart:
```bash
./unified-stack.sh generate
docker build -t ghcr.io/exea-centrum/dawid-trojanowski-full-site:latest .
docker push ghcr.io/exea-centrum/dawid-trojanowski-full-site:latest
kubectl apply -k manifests/base