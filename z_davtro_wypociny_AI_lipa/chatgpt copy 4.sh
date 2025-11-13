#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

# unified-stack.sh - All-in-one generator
# Generates:
# - app/ (FastAPI main.py, worker.py, templates/index.html, requirements.txt)
# - Dockerfile
# - .github/workflows/ci-cd.yaml (fixed for GHCR + GHCR_PAT)
# - manifests/base/* (app, worker, postgres, pgadmin, vault, redis, redis-insight, kafka, kafka-ui,
# prometheus, grafana, loki, promtail, tempo, ingress, kyverno, kustomization)
# - argocd-application.yaml
# - README.md
#
# Usage:
# chmod +x unified-stack.sh
# ./unified-stack.sh generate
#
# Notes:
# - Workflow expects secrets.GHCR_PAT to be configured (or change to use GITHUB_TOKEN).
# - Vault manifest includes disable_mlock = true to avoid IPC_LOCK issues on some nodes.
# - This is a teaching/demo scaffold. Replace credentials and remove dev-mode patterns before production.

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

info(){ printf "🔧 [unified] %s\n" "$*"; }
mkdir_p(){ mkdir -p "$@"; }

generate_structure(){
  info "Creating directories..."
  mkdir_p "$APP_DIR" "$TEMPLATES_DIR" "$BASE_DIR" "$WORKFLOW_DIR" "${ROOT_DIR}/static"
}

generate_fastapi_app(){
  info "Generating FastAPI app (main.py, worker.py, templates, requirements)..."

  cat > "${APP_DIR}/main.py" <<'PY'
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
import os, json, time, logging
import redis
from pydantic import BaseModel
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
import hvac

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi")

app = FastAPI(title="Personal Website - Queue")
templates = Jinja2Templates(directory="templates")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "messages")

MESSAGE_PUSHED = Counter("app_message_pushed_total", "Number of messages pushed to Redis")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

Instrumentator().instrument(app).expose(app)

class SurveyResponse(BaseModel):
    question: str
    answer: str

def get_vault_secret(secret_path: str) -> dict:
    try:
        vault_addr = os.getenv("VAULT_ADDR", "http://vault:8200")
        vault_token = os.getenv("VAULT_TOKEN")
        if vault_token:
            client = hvac.Client(url=vault_addr, token=vault_token)
            secret = client.read(secret_path)
            if secret:
                return secret['data']['data']
        else:
            logger.warning("Vault token not available, using fallback")
    except Exception as e:
        logger.warning(f"Error fetching from Vault: {e}, using fallback")
    return {}

def get_database_config() -> str:
    vault_secret = get_vault_secret("secret/data/database/postgres")
    if vault_secret:
        return f"dbname={vault_secret.get('postgres-db', 'webdb')} user={vault_secret.get('postgres-user', 'webuser')} password={vault_secret.get('postgres-password', 'testpassword')} host={vault_secret.get('postgres-host', 'postgres-db')}"
    else:
        return os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db")

DB_CONN = get_database_config()

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    try:
        conn = psycopg2.connect(DB_CONN)
        cur = conn.cursor()
        cur.execute("INSERT INTO page_visits (page) VALUES ('home')")
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Error logging page visit: {e}")
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/api/contact")
async def submit_contact(email: str = Form(...), message: str = Form(...)):
    payload = {"type": "contact", "email": email, "message": message, "timestamp": time.time()}
    try:
        r = get_redis()
        r.rpush(REDIS_LIST, json.dumps(payload))
        MESSAGE_PUSHED.inc()
        logger.info("Queued contact: %s", payload)
        return {"status": "queued", "payload": payload}
    except Exception as e:
        logger.exception("Failed to queue contact")
        raise HTTPException(status_code=500, detail="Failed to enqueue contact")

@app.post("/api/survey/submit")
async def submit_survey(response: SurveyResponse):
    payload = {"type": "survey", "question": response.question, "answer": response.answer, "timestamp": time.time()}
    try:
        r = get_redis()
        r.rpush(REDIS_LIST, json.dumps(payload))
        MESSAGE_PUSHED.inc()
        logger.info("Queued survey: %s", payload)
        return {"status": "queued", "payload": payload}
    except Exception as e:
        logger.exception("Failed to queue survey")
        raise HTTPException(status_code=500, detail="Failed to enqueue survey")

@app.get("/api/survey/questions")
async def get_survey_questions():
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
            "text": "Jakie technologie Cię zainteresowały?",
            "type": "multiselect",
            "options": ["Python", "JavaScript", "React", "Kubernetes", "Docker", "PostgreSQL", "Vault"]
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
        },
        {
            "id": 6,
            "text": "Test AI jak to robi wykładowca na ćwiczeniach z studentami mają do wykorzystania obiekt",
            "type": "text",
            "placeholder": "Twoja odpowiedź na testowe pytanie..."
        }
    ]
    return questions

@app.get("/api/survey/stats")
async def get_survey_stats():
    try:
        conn = psycopg2.connect(DB_CONN)
        cur = conn.cursor()
        cur.execute("SELECT question, answer, COUNT(*) as count FROM survey_responses GROUP BY question, answer ORDER BY question, count DESC")
        responses = cur.fetchall()
        cur.execute("SELECT COUNT(*) FROM page_visits")
        total_visits = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM survey_responses")
        total_responses = cur.fetchone()[0]
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
            "total_responses": total_responses
        }
    except Exception as e:
        logger.error(f"Error fetching survey stats: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas pobierania statystyk")

@app.get("/health")
async def health():
    status = {"service": "fastapi", "status": "ok"}
    try:
        r = get_redis()
        r.ping()
        status["redis"] = "connected"
    except Exception as e:
        status["redis"] = "disconnected"
        status["error"] = str(e)
    return status

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
PY

  cat > "${APP_DIR}/worker.py" <<'PY'
import os, json, time, logging
import redis
from kafka import KafkaProducer
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "messages")

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "messages-topic")

DATABASE_URL = os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    try:
        return KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP.split(','), value_serializer=lambda v: json.dumps(v).encode('utf-8'))
    except Exception as e:
        logger.exception("Kafka init error: %s", e)
        return None

def process_item(item, producer):
    try:
        if producer:
            producer.send(KAFKA_TOPIC, value=item)
            producer.flush()
        conn = psycopg2.connect(DATABASE_URL)
        cur = conn.cursor()
        if item.get("type") == "contact":
            cur.execute("INSERT INTO contact_messages (email, message) VALUES (%s, %s)", (item.get("email"), item.get("message")))
        elif item.get("type") == "survey":
            cur.execute("INSERT INTO survey_responses (question, answer) VALUES (%s, %s)", (item.get("question"), item.get("answer")))
        conn.commit()
        cur.close()
        conn.close()
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
                try:
                    item = json.loads(data)
                except Exception:
                    item = {"raw": data}
                process_item(item, producer)
        except Exception:
            logger.exception("Worker loop exception")
            time.sleep(2)

if __name__ == "__main__":
    main()
PY

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
      @keyframes fadeIn {
        from {
          opacity: 0;
          transform: translateY(10px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      @keyframes typewriter {
        from {
          width: 0;
        }
        to {
          width: 100%;
        }
      }
      @keyframes blink {
        from,
        to {
          border-color: transparent;
        }
        50% {
          border-color: #c084fc;
        }
      }
      .animate-fade-in {
        animation: fadeIn 0.5s ease-out;
      }
      .typewriter {
        overflow: hidden;
        border-right: 2px solid #c084fc;
        white-space: nowrap;
        animation: typewriter 2s steps(40, end), blink 0.75s step-end infinite;
      }
      .parallax {
        background-attachment: fixed;
        background-position: center;
        background-repeat: no-repeat;
        background-size: cover;
      }
      .particle {
        position: absolute;
        border-radius: 50%;
        background: radial-gradient(
          circle,
          rgba(168, 85, 247, 0.7) 0%,
          rgba(236, 72, 153, 0.3) 70%,
          transparent 100%
        );
        pointer-events: none;
      }
      .skill-bar {
        height: 10px;
        background: rgba(255, 255, 255, 0.1);
        border-radius: 5px;
        overflow: hidden;
      }
      .skill-progress {
        height: 100%;
        border-radius: 5px;
        transition: width 1.5s ease-in-out;
      }
      .hamburger {
        display: none;
        flex-direction: column;
        cursor: pointer;
      }
      .hamburger span {
        width: 25px;
        height: 3px;
        background: #c084fc;
        margin: 3px 0;
        transition: 0.3s;
      }
      @media (max-width: 768px) {
        .hamburger {
          display: flex;
        }
        nav {
          position: fixed;
          top: 80px;
          right: -100%;
          width: 70%;
          height: calc(100vh - 80px);
          background: rgba(15, 23, 42, 0.95);
          backdrop-filter: blur(10px);
          flex-direction: column;
          padding: 20px;
          transition: 0.5s;
          border-left: 1px solid rgba(168, 85, 247, 0.3);
        }
        nav.active {
          right: 0;
        }
        .tab-btn {
          margin: 10px 0;
          text-align: left;
          padding: 15px;
          border-radius: 8px;
          width: 100%;
        }
        .hamburger.active span:nth-child(1) {
          transform: rotate(-45deg) translate(-5px, 6px);
        }
        .hamburger.active span:nth-child(2) {
          opacity: 0;
        }
        .hamburger.active span:nth-child(3) {
          transform: rotate(45deg) translate(-5px, -6px);
        }
      }
    </style>
  </head>
  <body
    class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen transition-colors duration-500"
  >
    <!-- Floating particles -->
    <div
      id="particles-container"
      class="fixed top-0 left-0 w-full h-full pointer-events-none z-0"
    ></div>

    <header
      class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20 sticky top-0 z-50 transition-colors duration-500"
    >
      <div class="container mx-auto px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <svg
              class="w-10 h-10 text-purple-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
              ></path>
            </svg>
            <h1
              class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent"
            >
              Dawid Trojanowski
            </h1>
          </div>

          <div class="flex items-center gap-4">
            <!-- Theme Toggle -->
            <button
              id="theme-toggle"
              class="p-2 rounded-full bg-purple-500/20 hover:bg-purple-500/40 transition-colors"
            >
              <svg
                id="sun-icon"
                class="w-6 h-6 text-yellow-300"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
                ></path>
              </svg>
              <svg
                id="moon-icon"
                class="w-6 h-6 text-purple-300 hidden"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
                ></path>
              </svg>
            </button>

            <!-- Hamburger Menu -->
            <div class="hamburger" id="hamburger">
              <span></span>
              <span></span>
              <span></span>
            </div>

            <nav id="nav-menu" class="flex gap-4">
              <button
                onclick="showTab('intro')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="intro"
              >
                O Mnie
              </button>
              <button
                onclick="showTab('edu')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="edu"
              >
                Edukacja
              </button>
              <button
                onclick="showTab('exp')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="exp"
              >
                Doświadczenie
              </button>
              <button
                onclick="showTab('skills')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="skills"
              >
                Umiejętności
              </button>
              <button
                onclick="showTab('survey')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="survey"
              >
                Ankieta
              </button>
              <button
                onclick="showTab('contact')"
                class="tab-btn px-4 py-2 rounded-lg transition-all text-purple-300"
                data-tab="contact"
              >
                Kontakt
              </button>
            </nav>
          </div>
        </div>
      </div>
    </header>

    <main class="container mx-auto px-6 py-12 relative z-10">
      <div id="intro-tab" class="tab-content">
        <div class="space-y-8 animate-fade-in">
          <div
            class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8"
          >
            <h2 class="text-4xl font-bold mb-6 text-purple-300 typewriter">
              O Mnie
            </h2>
            <p class="text-lg text-gray-300 leading-relaxed mb-4">
              Cześć! Jestem Dawidem Trojanowskim, pasjonatem informatyki i
              nowych technologii. Zawsze dążyłem do rozwijania swoich
              umiejętności w programowaniu i rozwiązywaniu złożonych problemów.
              Moja ścieżka edukacyjna i zawodowa skupia się na informatyce
              stosowanej, gdzie łączę teorię z praktyką.
            </p>
            <p class="text-lg text-gray-300 leading-relaxed">
              Poza pracą interesuję się sportem, czytaniem książek i podróżami.
              Lubię wyzwania, które pozwalają mi rosnąć zarówno zawodowo, jak i
              osobowo.
            </p>
          </div>
          <div class="grid md:grid-cols-3 gap=6">
            <div
              class="bg-gradient-to-br from-blue-500/10 to-purple-500/10 backdrop-blur-lg border border-blue-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer"
              onclick="showTab('edu')"
            >
              <h3 class="text-xl font-bold mb-3 text-blue-300">Edukacja</h3>
              <p class="text-gray-400">
                Studia informatyczne na renomowanych uczelniach
              </p>
            </div>
            <div
              class="bg-gradient-to-br from-green-500/10 to-emerald-500/10 backdrop-blur-lg border border-green-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer"
              onclick="showTab('exp')"
            >
              <h3 class="text-xl font-bold mb-3 text-green-300">
                Doświadczenie
              </h3>
              <p class="text-gray-400">Praktyki i projekty w branży IT</p>
            </div>
            <div
              class="bg-gradient-to-br from-pink-500/10 to-rose-500/10 backdrop-blur-lg border border-pink-500/20 rounded-xl p-6 hover:scale-105 transition-transform cursor-pointer"
              onclick="showTab('survey')"
            >
              <h3 class="text-xl font-bold mb-3 text-pink-300">
                Ankieta
              </h3>
              <p class="text-gray-400">Podziel się opinią o stronie</p>
            </div>
          </div>
        </div>
      </div>

      <div id="edu-tab" class="tab-content hidden">
        <div class="space-y-6 animate-fade-in">
          <h2 class="text-4xl font-bold mb-8 text-purple-300">Edukacja</h2>
          <div
            class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
          >
            <h3 class="text-2xl font-bold mb-4 text-purple-300">
              Politechnika Warszawska
            </h3>
            <p class="text-gray-300 mb-4">Informatyka, studia magisterskie</p>
            <ul class="space-y-2">
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Specjalizacja w sztucznej inteligencji i uczeniu maszynowem
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Praca dyplomowa: "Zastosowanie sieci neuronowych w analizie
                danych"
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Średnia ocen: 4.5/5
              </li>
            </ul>
          </div>
          <div
            class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
          >
            <h3 class="text-2xl font-bold mb-4 text-purple-300">
              Uniwersytet Warszawski
            </h3>
            <p class="text-gray-300 mb-4">Informatyka, studia licencjackie</p>
            <ul class="space-y-2">
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Podstawy programowania i algorytmiki
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Projekty grupowe w Java i Python
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div id="exp-tab" class="tab-content hidden">
        <div class="space-y-6 animate-fade-in">
          <h2 class="text-4xl font-bold mb-8 text-purple-300">
            Doświadczenie Zawodowe
          </h2>
          <div
            class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
          >
            <h3 class="text-2xl font-bold mb-4 text-purple-300">
              Junior Developer - TechCorp
            </h3>
            <p class="text-gray-300 mb-4">Styczeń 2023 - Obecnie</p>
            <ul class="space-y-2">
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Rozwój aplikacji webowych w React i Node.js
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Optymalizacja baz danych SQL
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Współpraca z zespołem w metodologii Agile
              </li>
            </ul>
          </div>
          <div
            class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
          >
            <h3 class="text-2xl font-bold mb-4 text-purple-300">
              Praktykant - Startup AI
            </h3>
            <p class="text-gray-300 mb-4">Czerwiec 2022 - Sierpień 2022</p>
            <ul class="space-y-2">
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Implementacja modeli ML w Python
              </li>
              <li class="text-gray-400 flex items-center gap-2">
                <span class="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                Analiza danych z wykorzystaniem Pandas i Scikit-learn
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div id="skills-tab" class="tab-content hidden">
        <div class="space-y-6 animate-fade-in">
          <h2 class="text-4xl font-bold mb-8 text-purple-300">Umiejętności</h2>
          <div class="grid md:grid-cols-2 gap-6">
            <div
              class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
            >
              <h3 class="text-2xl font-bold mb-4 text-purple-300">
                Techniczne
              </h3>
              <div class="space-y-4">
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">Python</span>
                    <span class="text-purple-300">90%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="90%"
                    ></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">JavaScript</span>
                    <span class="text-purple-300">85%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="85%"
                    ></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">React</span>
                    <span class="text-purple-300">80%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="80%"
                    ></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">SQL</span>
                    <span class="text-purple-300">75%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="75%"
                    ></div>
                  </div>
                </div>
              </div>
            </div>
            <div
              class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6"
            >
              <h3 class="text-2xl font-bold mb-4 text-purple-300">Języki</h3>
              <div class="space-y-4">
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">Polski</span>
                    <span class="text-purple-300">100%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="100%"
                    ></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">Angielski</span>
                    <span class="text-purple-300">85%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="85%"
                    ></div>
                  </div>
                </div>
                <div>
                  <div class="flex justify-between mb-1">
                    <span class="text-gray-300">Niemiecki</span>
                    <span class="text-purple-300">40%</span>
                  </div>
                  <div class="skill-bar">
                    <div
                      class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500"
                      data-width="40%"
                    ></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- NOWA ZAKŁADKA: ANKIETA -->
      <div id="survey-tab" class="tab-content hidden">
        <div class="space-y-8 animate-fade-in">
          <div
            class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8"
          >
            <h2 class="text-4xl font-bold mb-6 text-purple-300">Ankieta</h2>
            <p class="text-lg text-gray-300 mb-8">
              Podziel się swoją opinią o mojej stronie! Twoje odpowiedzi pomogą mi ulepszyć treści i design.
            </p>
           
            <form id="survey-form" class="space-y-6">
              <div id="survey-questions">
                <!-- Pytania będą ładowane dynamicznie -->
              </div>
             
              <button
                type="submit"
                class="w-full py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all"
              >
                Wyślij ankietę
              </button>
            </form>
           
            <div id="survey-message" class="mt-4 hidden p-3 rounded-lg"></div>
          </div>

          <div
            class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8"
          >
            <h3 class="text-2xl font-bold mb-6 text-purple-300">Statystyki ankiet</h3>
            <div class="grid md:grid-cols-2 gap-6">
              <div class="space-y-4">
                <div id="survey-stats">
                  <!-- Statystyki będą ładowane dynamicznie -->
                </div>
              </div>
              <div class="space-y-4">
                <canvas id="survey-chart" width="400" height="200"></canvas>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div id="contact-tab" class="tab-content hidden">
        <div class="space-y-8 animate-fade-in">
          <div
            class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8"
          >
            <h2 class="text-4xl font-bold mb-6 text-purple-300">Kontakt</h2>
            <p class="text-lg text-gray-300 mb-8">
              Chętnie porozmawiam o możliwościach współpracy lub po prostu o
              pasjach!
            </p>
            <div class="grid md:grid-cols-2 gap-6">
              <div class="space-y-4">
                <form id="contact-form">
                  <div>
                    <label class="block text-gray-400 mb-2">Email</label>
                    <input
                      type="email"
                      id="email-input"
                      name="email"
                      placeholder="Twój email"
                      class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30 focus:border-purple-400 outline-none transition-colors"
                      required
                    />
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-2">Wiadomość</label>
                    <textarea
                      id="message-input"
                      name="message"
                      placeholder="Twoja wiadomość"
                      rows="4"
                      class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30 focus:border-purple-400 outline-none transition-colors"
                      required
                    ></textarea>
                  </div>
                  <button
                    type="submit"
                    id="send-btn"
                    class="w-full mt-4 py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all"
                  >
                    Wyślij
                  </button>
                </form>
                <div id="form-message" class="mt-4 hidden p-3 rounded-lg"></div>
              </div>
              <div class="space-y-4">
                <div
                  class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"
                >
                  <p class="text-gray-400 mb-1">Email</p>
                  <p class="text-purple-300">dawid.trojanowski@example.com</p>
                </div>
                <div
                  class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"
                >
                  <p class="text-gray-400 mb-1">LinkedIn</p>
                  <p class="text-purple-300">
                    linkedin.com/in/dawid-trojanowski
                  </p>
                </div>
                <div
                  class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"
                >
                  <p class="text-gray-400 mb-1">GitHub</p>
                  <p class="text-purple-300">github.com/dawidtrojanowski</p>
                </div>
                <div
                  class="bg-slate-800/50 rounded-xl p-4 hover:bg-slate-700/50 transition-colors"
                >
                  <p class="text-gray-400 mb-1">Telefon</p>
                  <p class="text-purple-300">+48 123 456 789</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <footer
      class="border-t border-purple-500/30 backdrop-blur-sm bg-black/20 mt-16 transition-colors duration-500"
    >
      <div class="container mx-auto px-6 py-8 text-center text-gray-400">
        <p>Dawid Trojanowski © 2025</p>
      </div>
    </footer>

    <script>
      // Tab switching functionality
      function showTab(tabName) {
        document.querySelectorAll(".tab-content").forEach((tab) => {
          tab.classList.add("hidden");
          tab.classList.remove("animate-fade-in");
        });

        setTimeout(() => {
          const activeTab = document.getElementById(tabName + "-tab");
          activeTab.classList.remove("hidden");
          activeTab.classList.add("animate-fade-in");

          // Animate skill bars when skills tab is shown
          if (tabName === "skills") {
            setTimeout(animateSkillBars, 300);
          }
         
          // Load survey data when survey tab is shown
          if (tabName === "survey") {
            loadSurveyQuestions();
            loadSurveyStats();
          }
        }, 50);

        document.querySelectorAll(".tab-btn").forEach((btn) => {
          btn.classList.remove("bg-purple-500", "text-white");
          btn.classList.add("text-purple-300");
        });
        document
          .querySelector(`[data-tab="${tabName}"]`)
          .classList.add("bg-purple-500", "text-white");

        // Close mobile menu if open
        closeMobileMenu();
      }

      // Theme toggle functionality
      const themeToggle = document.getElementById("theme-toggle");
      const sunIcon = document.getElementById("sun-icon");
      const moonIcon = document.getElementById("moon-icon");

      themeToggle.addEventListener("click", () => {
        document.body.classList.toggle("light-mode");

        if (document.body.classList.contains("light-mode")) {
          document.body.className =
            "bg-gradient-to-br from-slate-100 via-purple-100 to-slate-100 text-slate-800 min-h-screen transition-colors duration-500";
          sunIcon.classList.add("hidden");
          moonIcon.classList.remove("hidden");
        } else {
          document.body.className =
            "bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen transition-colors duration-500";
          sunIcon.classList.remove("hidden");
          moonIcon.classList.add("hidden");
        }
      });

      // Mobile menu functionality
      const hamburger = document.getElementById("hamburger");
      const navMenu = document.getElementById("nav-menu");

      function toggleMobileMenu() {
        hamburger.classList.toggle("active");
        navMenu.classList.toggle("active");
      }

      function closeMobileMenu() {
        hamburger.classList.remove("active");
        navMenu.classList.remove("active");
      }

      hamburger.addEventListener("click", toggleMobileMenu);

      // Close menu when clicking outside
      document.addEventListener("click", (e) => {
        if (!hamburger.contains(e.target) && !navMenu.contains(e.target)) {
          closeMobileMenu();
        }
      });

      // Skill bars animation
      function animateSkillBars() {
        const skillBars = document.querySelectorAll(".skill-progress");
        skillBars.forEach((bar) => {
          const width = bar.getAttribute("data-width");
          bar.style.width = width;
        });
      }

      // Contact form functionality
      document.getElementById('contact-form').addEventListener('submit', async (e) => {
        e.preventDefault();
       
        const email = document.getElementById('email-input').value.trim();
        const message = document.getElementById('message-input').value.trim();
        const formMessage = document.getElementById('form-message');

        if (!email || !message) {
          showFormMessage("Proszę wypełnić wszystkie pola", "error");
          return;
        }

        if (!validateEmail(email)) {
          showFormMessage("Proszę podać poprawny adres email", "error");
          return;
        }

        try {
          const formData = new FormData();
          formData.append('email', email);
          formData.append('message', message);

          const response = await fetch('/api/contact', {
            method: 'POST',
            body: formData
          });

          const result = await response.json();

          if (response.ok) {
            showFormMessage(result.message, "success");
            document.getElementById('email-input').value = "";
            document.getElementById('message-input').value = "";
          } else {
            showFormMessage(result.detail || "Wystąpił błąd podczas wysyłania", "error");
          }
        } catch (error) {
          console.error('Error sending contact form:', error);
          showFormMessage("Wystąpił błąd podczas wysyłania wiadomości", "error");
        }
      });

      function validateEmail(email) {
        const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return re.test(email);
      }

      function showFormMessage(text, type) {
        const formMessage = document.getElementById('form-message');
        formMessage.textContent = text;
        formMessage.className = "mt-4 p-3 rounded-lg";

        if (type === "error") {
          formMessage.classList.add(
            "bg-red-500/20",
            "text-red-300",
            "border",
            "border-red-500/30"
          );
        } else {
          formMessage.classList.add(
            "bg-green-500/20",
            "text-green-300",
            "border",
            "border-green-500/30"
          );
        }

        formMessage.classList.remove("hidden");

        setTimeout(() => {
          formMessage.classList.add("hidden");
        }, 5000);
      }

      // Floating particles effect
      function createParticles() {
        const container = document.getElementById("particles-container");
        const particleCount = 30;

        for (let i = 0; i < particleCount; i++) {
          const particle = document.createElement("div");
          particle.classList.add("particle");

          const size = Math.random() * 60 + 20;
          particle.style.width = `${size}px`;
          particle.style.height = `${size}px`;

          particle.style.left = `${Math.random() * 100}%`;
          particle.style.top = `${Math.random() * 100}%`;

          const animationDuration = Math.random() * 20 + 10;
          particle.style.animation = `float ${animationDuration}s infinite ease-in-out`;

          container.appendChild(particle);
        }
      }

      // Survey functionality
      async function loadSurveyQuestions() {
        try {
          const response = await fetch('/api/survey/questions');
          const questions = await response.json();
         
          const container = document.getElementById('survey-questions');
          container.innerHTML = '';
         
          questions.forEach((q, index) => {
            const questionDiv = document.createElement('div');
            questionDiv.className = 'space-y-3';
           
            questionDiv.innerHTML = `
              <label class="block text-gray-300 font-semibold">
                ${q.text}
              </label>
            `;
           
            if (q.type === 'rating') {
              questionDiv.innerHTML += `
                <div class="flex gap-2 flex-wrap">
                  ${q.options.map(option => `
                    <label class="flex items-center space-x-2 cursor-pointer">
                      <input type="radio" name="question_${q.id}" value="${option}" class="hidden peer" required>
                      <span class="px-4 py-2 rounded-lg bg-slate-700 text-gray-300 peer-checked:bg-purple-500 peer-checked:text-white transition-all hover:bg-slate-600">
                        ${option}
                      </span>
                    </label>
                  `).join('')}
                </div>
              `;
            } else if (q.type === 'choice') {
              questionDiv.innerHTML += `
                <div class="space-y-2">
                  ${q.options.map(option => `
                    <label class="flex items-center space-x-3 cursor-pointer">
                      <input type="radio" name="question_${q.id}" value="${option}" class="text-purple-500 focus:ring-purple-500" required>
                      <span class="text-gray-300">${option}</span>
                    </label>
                  `).join('')}
                </div>
              `;
            } else if (q.type === 'multiselect') {
              questionDiv.innerHTML += `
                <div class="space-y-2">
                  ${q.options.map(option => `
                    <label class="flex items-center space-x-3 cursor-pointer">
                      <input type="checkbox" name="question_${q.id}" value="${option}" class="text-purple-500 focus:ring-purple-500">
                      <span class="text-gray-300">${option}</span>
                    </label>
                  `).join('')}
                </div>
              `;
            } else if (q.type === 'text') {
              questionDiv.innerHTML += `
                <textarea
                  name="question_${q.id}"
                  placeholder="${q.placeholder}"
                  class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30 focus:border-purple-400 outline-none transition-colors"
                  rows="3"
                ></textarea>
              `;
            }
           
            container.appendChild(questionDiv);
          });
        } catch (error) {
          console.error('Error loading survey questions:', error);
        }
      }

      async function loadSurveyStats() {
        try {
          const response = await fetch('/api/survey/stats');
          const stats = await response.json();
         
          const container = document.getElementById('survey-stats');
         
          if (stats.total_responses === 0) {
            container.innerHTML = `
              <div class="text-center text-gray-400 py-8">
                <p>Brak odpowiedzi na ankietę.</p>
                <p class="text-sm mt-2">Bądź pierwszą osobą która wypełni ankietę!</p>
              </div>
            `;
            return;
          }
         
          let statsHTML = `
            <div class="space-y-4">
              <div class="grid grid-cols-2 gap-4 text-center">
                <div class="bg-slate-800/50 rounded-lg p-4">
                  <div class="text-2xl font-bold text-purple-300">${stats.total_visits}</div>
                  <div class="text-sm text-gray-400">Odwiedzin</div>
                </div>
                <div class="bg-slate-800/50 rounded-lg p-4">
                  <div class="text-2xl font-bold text-purple-300">${stats.total_responses}</div>
                  <div class="text-sm text-gray-400">Odpowiedzi</div>
                </div>
              </div>
          `;
         
          for (const [question, answers] of Object.entries(stats.survey_responses)) {
            statsHTML += `
              <div class="border-t border-purple-500/20 pt-4">
                <h4 class="font-semibold text-purple-300 mb-2">${question}</h4>
                <div class="space-y-2">
            `;
           
            answers.forEach(item => {
              statsHTML += `
                <div class="flex justify-between items-center">
                  <span class="text-gray-300 text-sm">${item.answer}</span>
                  <span class="text-purple-300 font-semibold">${item.count}</span>
                </div>
              `;
            });
           
            statsHTML += `
                </div>
              </div>
            `;
          }
         
          statsHTML += `</div>`;
          container.innerHTML = statsHTML;
         
          // Update chart if there are responses
          updateSurveyChart(stats);
        } catch (error) {
          console.error('Error loading survey stats:', error);
          document.getElementById('survey-stats').innerHTML = `
            <div class="text-red-300 text-center py-4">
              Błąd podczas ładowania statystyk
            </div>
          `;
        }
      }

      function updateSurveyChart(stats) {
        const ctx = document.getElementById('survey-chart').getContext('2d');
       
        // Prepare data for chart
        const labels = [];
        const data = [];
       
        for (const [question, answers] of Object.entries(stats.survey_responses)) {
          answers.forEach(item => {
            labels.push(`${question}: ${item.answer}`);
            data.push(item.count);
          });
        }
       
        new Chart(ctx, {
          type: 'doughnut',
          data: {
            labels: labels,
            datasets: [{
              data: data,
              backgroundColor: [
                '#a855f7', '#ec4899', '#8b5cf6', '#d946ef', '#7c3aed',
                '#c026d3', '#6d28d9', '#a21caf', '#5b21b6', '#86198f'
              ],
              borderWidth: 2,
              borderColor: '#1e293b'
            }]
          },
          options: {
            responsive: true,
            plugins: {
              legend: {
                position: 'bottom',
                labels: {
                  color: '#cbd5e1',
                  font: {
                    size: 10
                  }
                }
              }
            }
          }
        });
      }

      // Survey form submission
      document.getElementById('survey-form').addEventListener('submit', async (e) => {
        e.preventDefault();
       
        const formData = new FormData(e.target);
        const responses = [];
       
        // Collect all responses
        for (let i = 1; i <= 6; i++) {  // Updated to 6 questions
          const questionName = `question_${i}`;
          const questionElement = e.target.elements[questionName];
         
          if (questionElement) {
            if (questionElement.type === 'radio') {
              const selected = document.querySelector(`input[name="question_${i}"]:checked`);
              if (selected) {
                responses.push({
                  question: `Pytanie ${i}: ${document.querySelector(\`label[for="question_${i}"]\`)?.textContent || questionName}`,
                  answer: selected.value
                });
              }
            } else if (questionElement.type === 'checkbox') {
              const selected = document.querySelectorAll(`input[name="question_${i}"]:checked`);
              if (selected.length > 0) {
                const answers = Array.from(selected).map(cb => cb.value).join(', ');
                responses.push({
                  question: `Pytanie ${i}: ${document.querySelector(\`label[for="question_${i}"]\`)?.textContent || questionName}`,
                  answer: answers
                });
              }
            } else if (questionElement.tagName === 'TEXTAREA' && questionElement.value.trim()) {
              responses.push({
                question: `Pytanie ${i}: ${document.querySelector(\`label[for="question_${i}"]\`)?.textContent || questionName}`,
                answer: questionElement.value.trim()
              });
            }
          }
        }
       
        if (responses.length === 0) {
          showSurveyMessage('Proszę odpowiedzieć na przynajmniej jedno pytanie', 'error');
          return;
        }
       
        try {
          // Send each response
          for (const response of responses) {
            await fetch('/api/survey/submit', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(response)
            });
          }
         
          showSurveyMessage('Dziękujemy za wypełnienie ankiety!', 'success');
          e.target.reset();
          loadSurveyStats(); // Reload stats
        } catch (error) {
          console.error('Error submitting survey:', error);
          showSurveyMessage('Wystąpił błąd podczas wysyłania ankiety', 'error');
        }
      });

      function showSurveyMessage(text, type) {
        const messageDiv = document.getElementById('survey-message');
        messageDiv.textContent = text;
        messageDiv.className = 'mt-4 p-3 rounded-lg';
       
        if (type === 'error') {
          messageDiv.classList.add('bg-red-500/20', 'text-red-300', 'border', 'border-red-500/30');
        } else {
          messageDiv.classList.add('bg-green-500/20', 'text-green-300', 'border', 'border-green-500/30');
        }
       
        messageDiv.classList.remove('hidden');
       
        setTimeout(() => {
          messageDiv.classList.add('hidden');
        }, 5000);
      }

      // Initialize on page load
      document.addEventListener("DOMContentLoaded", () => {
        showTab("intro");
        createParticles();

        // Add floating animation
        const style = document.createElement("style");
        style.textContent = `
          @keyframes float {
            0%, 100% { transform: translate(0, 0) rotate(0deg); }
            25% { transform: translate(10px, -10px) rotate(5deg); }
            50% { transform: translate(-5px, 5px) rotate(-5deg); }
            75% { transform: translate(-10px, -5px) rotate(3deg); }
          }
        `;
        document.head.appendChild(style);
      });
    </script>
  </body>
</html>
HTML

  cat > "${APP_DIR}/requirements.txt" <<'REQ'
fastapi==0.104.1
uvicorn==0.24.0
jinja2==3.1.2
psycopg2-binary==2.9.7
prometheus-fastapi-instrumentator==5.11.1
prometheus-client==0.16.0
python-multipart==0.0.6
pydantic==2.5.0
kafka-python==2.0.2
hvac==1.1.0
redis==4.6.0
REQ

  chmod +x "${APP_DIR}/worker.py"
  info "FastAPI app generated."
}

generate_dockerfile(){
  info "Generating Dockerfile..."
  cat > "${ROOT_DIR}/Dockerfile" <<'DOCK'
FROM python:3.11-slim-bullseye
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ /app/
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCK
  info "Dockerfile written."
}

generate_github_actions(){
  info "Writing GitHub Actions workflow (.github/workflows/ci-cd.yaml)..."
  mkdir_p "$WORKFLOW_DIR"
  # Use escaped ${{ ... }} sequences so this script writes the intended Actions expressions into the YAML
  cat > "${WORKFLOW_DIR}/ci-cd.yaml" <<'YAML'
name: CI/CD Build & Deploy

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui

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
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT }}

      - name: Debug: show resolved REGISTRY
        run: |
          echo "REGISTRY=${{ env.REGISTRY }}"
          docker --version

      - name: Build and push image
        uses: docker/build-push-action@v5
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
  info "Workflow written."
}

generate_k8s_manifests(){
  info "Generating Kubernetes manifests (manifests/base)..."
  mkdir_p "$BASE_DIR"

  # app deployment + service + sa
  cat > "${BASE_DIR}/app-deployment.yaml" <<YAML
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
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 20
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8000
  selector:
    app: ${PROJECT}
    component: fastapi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: ${NAMESPACE}
YAML

  # message-processor
  cat > "${BASE_DIR}/message-processor.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: worker
    spec:
      serviceAccountName: fastapi-sa
      containers:
      - name: worker
        image: ${REGISTRY}:latest
        command: ["python", "worker.py"]
        env:
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
YAML

  # postgres
  cat > "${BASE_DIR}/postgres-db.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 5432
    name: postgres
  selector:
    app: ${PROJECT}
    component: postgres
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
    matchLabels:
      app: ${PROJECT}
      component: postgres
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_USER
          value: "webuser"
        - name: POSTGRES_PASSWORD
          value: "testpassword"
        - name: POSTGRES_DB
          value: "webdb"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
YAML

  # pgadmin
  cat > "${BASE_DIR}/pgadmin.yaml" <<YAML
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
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: "admin@webstack.local"
        - name: PGADMIN_DEFAULT_PASSWORD
          value: "adminpassword"
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin-service
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: pgadmin
YAML

  # vault (service + statefulset) - disable_mlock set to true; securityContext adds IPC_LOCK (optional)
  cat > "${BASE_DIR}/vault.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  ports:
  - name: http
    port: 8200
  selector:
    app: vault
    component: vault
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
    matchLabels:
      app: vault
      component: vault
  template:
    metadata:
      labels:
        app: vault
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
          value: |
            listener "tcp" {
              address = "0.0.0.0:8200"
              tls_disable = "true"
            }
            storage "file" {
              path = "/vault/file"
            }
            disable_mlock = true
            ui = true
        securityContext:
          capabilities:
            add: ["IPC_LOCK"]
        volumeMounts:
        - name: vault-data
          mountPath: /vault/file
  volumeClaimTemplates:
  - metadata:
      name: vault-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
YAML

  # redis + redis-insight
  cat > "${BASE_DIR}/redis.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
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
        image: redis:7-alpine
        command: ["redis-server","--appendonly","yes"]
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
YAML

  cat > "${BASE_DIR}/redis-insight.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-insight
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-insight
  template:
    metadata:
      labels:
        app: redis-insight
    spec:
      containers:
      - name: redis-insight
        image: redislabs/redisinsight:latest
        ports:
        - containerPort: 8001
---
apiVersion: v1
kind: Service
metadata:
  name: redis-insight
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 8001
    targetPort: 8001
  selector:
    app: redis-insight
YAML

  # kafka-kraft (single node)
  cat > "${BASE_DIR}/kafka-kraft.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  ports:
  - port: 9092
    name: client
  - port: 9093
    name: inter
  selector:
    app: kafka
    component: kafka
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
      component: kafka
  template:
    metadata:
      labels:
        app: kafka
        component: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:3.6.1
        env:
        - name: KAFKA_CFG_NODE_ID
          value: "1"
        - name: KAFKA_CFG_PROCESS_ROLES
          value: "controller,broker"
        - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
          value: "1@kafka:9093"
        - name: KAFKA_CFG_LISTENERS
          value: "CLIENT://:9092,INTERNAL://:9093"
        - name: KAFKA_CFG_ADVERTISED_LISTENERS
          value: "CLIENT://kafka:9092,INTERNAL://kafka:9093"
        - name: KAFKA_CFG_KRAFT_CLUSTER_ID
          value: "${KAFKA_CLUSTER_ID}"
        ports:
        - containerPort: 9092
YAML

  # kafka-ui
  cat > "${BASE_DIR}/kafka-ui.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: kafka-ui
YAML

  # prometheus config + deployment
  cat > "${BASE_DIR}/prometheus-config.yaml" <<YAML
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
        static_configs:
          - targets: ['fastapi-web-service:80']
YAML

  cat > "${BASE_DIR}/prometheus.yaml" <<YAML
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
        image: prom/prometheus:v2.48.0
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
  name: prometheus-service
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 9090
    targetPort: 9090
  selector:
    app: prometheus
YAML

  # grafana datasource + deployment
  cat > "${BASE_DIR}/grafana-datasource.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: ${NAMESPACE}
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-service:9090
      isDefault: true
YAML

  cat > "${BASE_DIR}/grafana.yaml" <<YAML
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
        image: grafana/grafana:10.2.2
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: admin
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: admin
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 3000
  selector:
    app: grafana
YAML

  # loki + promtail
  cat > "${BASE_DIR}/loki-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
data:
  loki.yaml: |
    server:
      http_listen_port: 3100
YAML

  cat > "${BASE_DIR}/loki.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  serviceName: loki
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
        image: grafana/loki:2.9.2
        ports:
        - containerPort: 3100
YAML

  cat > "${BASE_DIR}/promtail-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: ${NAMESPACE}
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
    clients:
      - url: http://loki:3100/loki/api/v1/push
YAML

  cat > "${BASE_DIR}/promtail.yaml" <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: ${NAMESPACE}
spec:
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
        image: grafana/promtail:2.9.2
YAML

  # tempo
  cat > "${BASE_DIR}/tempo-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
YAML

  cat > "${BASE_DIR}/tempo.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tempo
  namespace: ${NAMESPACE}
spec:
  serviceName: tempo
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
        image: grafana/tempo:2.4.2
        ports:
        - containerPort: 3200
YAML

  # ingress
  cat > "${BASE_DIR}/ingress.yaml" <<YAML
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
YAML

  # kyverno
  cat > "${BASE_DIR}/kyverno-policy.yaml" <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-requests-limits
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: check-container-resources
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "All containers must define 'requests' and 'limits' for CPU and memory."
      foreach:
      - variables:
          element: "{{ request.object.spec.containers[] }}"
        deny:
          conditions:
            any:
            - key: "{{ element.resources.requests.cpu || '' }}"
              operator: Equals
              value: ""
            - key: "{{ element.resources.limits.cpu || '' }}"
              operator: Equals
              value: ""
YAML

  # kustomization
  cat > "${BASE_DIR}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
  - app-deployment.yaml
  - message-processor.yaml
  - postgres-db.yaml
  - pgadmin.yaml
  - vault.yaml
  - redis.yaml
  - redis-insight.yaml
  - kafka-kraft.yaml
  - kafka-ui.yaml
  - prometheus-config.yaml
  - prometheus.yaml
  - grafana-datasource.yaml
  - grafana.yaml
  - loki-config.yaml
  - loki.yaml
  - promtail-config.yaml
  - promtail.yaml
  - tempo-config.yaml
  - tempo.yaml
  - ingress.yaml
  - kyverno-policy.yaml

commonLabels:
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: kustomize
YAML

  # argocd application
  cat > "${ROOT_DIR}/argocd-application.yaml" <<YAML
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
    automated:
      prune: true
      selfHeal: true
YAML

  info "Kubernetes manifests written to ${BASE_DIR}."
}

generate_readme(){
  info "Generating README.md..."
  cat > "${ROOT_DIR}/README.md" <<README
# ${PROJECT} - All-in-one teaching stack

This repository is generated by unified-stack.sh and contains:
- FastAPI app + worker (app/)
- Dockerfile
- K8s manifests in manifests/base/
- GitHub Actions workflow (.github/workflows/ci-cd.yaml)
- README & ArgoCD application manifest

Quickstart:
1. Generate files:
   ./unified-stack.sh generate
2. Build & push image:
   docker build -t ${REGISTRY}:latest .
   docker push ${REGISTRY}:latest
3. Deploy:
   kubectl apply -k manifests/base

Notes:
- Vault runs with disable_mlock=true in manifest to avoid IPC_LOCK issues on some nodes.
- Replace example passwords and Vault dev-mode with proper secrets before production.
- Dane z formularzy (contact i survey) przechodzą przez Redis -> Kafka -> Postgres.
README
  info "README written."
}

generate_all(){
  info "Starting generation..."
  generate_structure
  generate_fastapi_app
  generate_dockerfile
  generate_github_actions
  generate_k8s_manifests
  generate_readme
  echo
  info "✅ Generation complete. Files created under: ${ROOT_DIR}"
  echo "Next: build image -> push -> kubectl apply -k manifests/base"
}

case "${1:-}" in
  generate) generate_all ;;
  help|-h|--help)
    cat <<EOF
Usage: $0 generate
Generates an all-in-one project scaffold (app, manifests, dockerfile, CI).
EOF
    ;;
  *)
    echo "Unknown command. Use: $0 help"
    exit 1
    ;;
esac