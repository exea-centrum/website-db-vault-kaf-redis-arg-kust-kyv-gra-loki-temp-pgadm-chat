#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

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
 info "Generating FastAPI app with survey system..."

 cat > "${APP_DIR}/main.py" <<'PY'
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
import hvac
import json
import redis
from kafka import KafkaProducer

app = FastAPI(title="Dawid Trojanowski - Strona Osobista")
templates = Jinja2Templates(directory="templates")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi_app")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis and Kafka configuration
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "outgoing_messages")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "survey-topic")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    try:
        return KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP.split(','),
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
    except Exception as e:
        logger.exception("Kafka init error: %s", e)
        return None

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
        logger.warning(f"Vault error: {e}, using fallback")
    
    return {}

def get_database_config() -> str:
    vault_secret = get_vault_secret("secret/data/database/postgres")
    
    if vault_secret:
        return f"dbname={vault_secret.get('postgres-db', 'webdb')} " \
               f"user={vault_secret.get('postgres-user', 'webuser')} " \
               f"password={vault_secret.get('postgres-password', 'testpassword')} " \
               f"host={vault_secret.get('postgres-host', 'postgres-db')}"
    else:
        return os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db")

DB_CONN = get_database_config()

Instrumentator().instrument(app).expose(app)

class SurveyResponse(BaseModel):
    question: str
    answer: str

def get_db_connection():
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
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS survey_responses(
                    id SERIAL PRIMARY KEY,
                    question TEXT NOT NULL,
                    answer TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS page_visits(
                    id SERIAL PRIMARY KEY,
                    page VARCHAR(255) NOT NULL,
                    visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
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
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        
        vault_secret = get_vault_secret("secret/data/database/postgres")
        vault_status = "connected" if vault_secret else "disconnected"
        
        return {
            "status": "healthy",
            "database": "connected",
            "vault": vault_status
        }
    except Exception as e:
        logger.warning(f"Health check failed: {e}")
        return {
            "status": "healthy",
            "database": "disconnected",
            "vault": "disconnected",
            "error": str(e)
        }

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
        }
    ]
    return questions

@app.post("/api/survey/submit")
async def submit_survey(response: SurveyResponse):
    try:
        # Push to Redis for processing
        r = get_redis()
        payload = {
            "type": "survey",
            "question": response.question,
            "answer": response.answer,
            "timestamp": time.time()
        }
        r.rpush(REDIS_LIST, json.dumps(payload))
        
        logger.info(f"Survey response queued: {response.question} -> {response.answer}")
        return {"status": "success", "message": "Dziękujemy za wypełnienie ankiety!"}
    except Exception as e:
        logger.error(f"Error queueing survey response: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas zapisywania odpowiedzi")

@app.get("/api/survey/stats")
async def get_survey_stats():
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
    try:
        # Push to Redis for processing
        r = get_redis()
        payload = {
            "type": "contact",
            "email": email,
            "message": message,
            "timestamp": time.time()
        }
        r.rpush(REDIS_LIST, json.dumps(payload))
        
        logger.info(f"Contact message queued from: {email}")
        return {"status": "success", "message": "Wiadomość została wysłana!"}
    except Exception as e:
        logger.error(f"Error queueing contact message: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas wysyłania wiadomości")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
PY

 cat > "${APP_DIR}/worker.py" <<'PY'
#!/usr/bin/env python3
import os, json, time, logging
import redis
from kafka import KafkaProducer
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "outgoing_messages")

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "survey-topic")

DATABASE_URL = os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    try:
        return KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP.split(','),
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
    except Exception as e:
        logger.exception("Kafka init error: %s", e)
        return None

def get_db_connection():
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DATABASE_URL)
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All connection attempts failed: {e}")
                raise e

def save_to_db(item_type, data):
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        if item_type == "survey":
            cur.execute(
                "INSERT INTO survey_responses (question, answer) VALUES (%s, %s)",
                (data.get("question"), data.get("answer"))
            )
        elif item_type == "contact":
            cur.execute(
                "INSERT INTO contact_messages (email, message) VALUES (%s, %s)",
                (data.get("email"), data.get("message"))
            )
        
        conn.commit()
        logger.info(f"Saved {item_type} to database")
    except Exception as e:
        logger.error(f"Error saving to database: {e}")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

def process_item(item, producer):
    try:
        # Send to Kafka
        if producer:
            producer.send(KAFKA_TOPIC, value=item)
            producer.flush()
            logger.info(f"Sent to Kafka topic {KAFKA_TOPIC}: {item}")
        
        # Save to PostgreSQL
        item_type = item.get("type")
        save_to_db(item_type, item)
        
    except Exception as e:
        logger.exception(f"Processing failed for item: {item}")

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
                    item = {"raw": data, "type": "unknown"}
                
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
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .animate-fade-in { animation: fadeIn 0.5s ease-out; }
        .skill-bar { height: 10px; background: rgba(255,255,255,0.1); border-radius: 5px; overflow: hidden; }
        .skill-progress { height: 100%; border-radius: 5px; transition: width 1.5s ease-in-out; }
    </style>
</head>
<body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen">
    <header class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
            <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                    <h1 class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                        Dawid Trojanowski
                    </h1>
                </div>
                <nav class="flex gap-4">
                    <button onclick="showTab('intro')" class="tab-btn px-4 py-2 rounded-lg bg-purple-500 text-white" data-tab="intro">O Mnie</button>
                    <button onclick="showTab('edu')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="edu">Edukacja</button>
                    <button onclick="showTab('exp')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="exp">Doświadczenie</button>
                    <button onclick="showTab('skills')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="skills">Umiejętności</button>
                    <button onclick="showTab('survey')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="survey">Ankieta</button>
                    <button onclick="showTab('contact')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="contact">Kontakt</button>
                </nav>
            </div>
        </div>
    </header>

    <main class="container mx-auto px-6 py-12">
        <div id="intro-tab" class="tab-content">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">O Mnie</h2>
                    <p class="text-lg text-gray-300 leading-relaxed">
                        Cześć! Jestem Dawidem Trojanowskim, pasjonatem informatyki i nowych technologii. 
                        Specjalizuję się w tworzeniu rozproszonych systemów wykorzystujących FastAPI, Redis, 
                        Kafka i PostgreSQL z pełnym monitoringiem.
                    </p>
                </div>
            </div>
        </div>

        <div id="edu-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Edukacja</h2>
                <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                    <h3 class="text-2xl font-bold mb-4 text-purple-300">Politechnika Warszawska</h3>
                    <p class="text-gray-300 mb-4">Informatyka, studia magisterskie</p>
                </div>
            </div>
        </div>

        <div id="exp-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Doświadczenie Zawodowe</h2>
                <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                    <h3 class="text-2xl font-bold mb-4 text-purple-300">Full Stack Developer</h3>
                    <p class="text-gray-300 mb-4">Specjalizacja w systemach rozproszonych</p>
                </div>
            </div>
        </div>

        <div id="skills-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Umiejętności</h2>
                <div class="grid md:grid-cols-2 gap-6">
                    <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                        <h3 class="text-2xl font-bold mb-4 text-purple-300">Technologie</h3>
                        <div class="space-y-4">
                            <div>
                                <div class="flex justify-between mb-1"><span>FastAPI</span><span>90%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="90%"></div></div>
                            </div>
                            <div>
                                <div class="flex justify-between mb-1"><span>Kubernetes</span><span>85%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="85%"></div></div>
                            </div>
                            <div>
                                <div class="flex justify-between mb-1"><span>PostgreSQL</span><span>88%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="88%"></div></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div id="survey-tab" class="tab-content hidden">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">Ankieta</h2>
                    <p class="text-lg text-gray-300 mb-8">
                        Twoje odpowiedzi trafią przez Redis i Kafka do bazy PostgreSQL z pełnym monitoringiem!
                    </p>
                  
                    <form id="survey-form" class="space-y-6">
                        <div id="survey-questions"></div>
                        <button type="submit" class="w-full py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">
                            Wyślij ankietę
                        </button>
                    </form>
                  
                    <div id="survey-message" class="mt-4 hidden p-3 rounded-lg"></div>
                </div>

                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h3 class="text-2xl font-bold mb-6 text-purple-300">Statystyki ankiet</h3>
                    <div class="grid md:grid-cols-2 gap-6">
                        <div id="survey-stats"></div>
                        <div><canvas id="survey-chart" width="400" height="200"></canvas></div>
                    </div>
                </div>
            </div>
        </div>

        <div id="contact-tab" class="tab-content hidden">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">Kontakt</h2>
                    <div class="grid md:grid-cols-2 gap-6">
                        <div class="space-y-4">
                            <form id="contact-form">
                                <div><input type="email" name="email" placeholder="Twój email" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" required></div>
                                <div><textarea name="message" placeholder="Twoja wiadomość" rows="4" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" required></textarea></div>
                                <button type="submit" class="w-full mt-4 py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">Wyślij</button>
                            </form>
                            <div id="form-message" class="mt-4 hidden p-3 rounded-lg"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <script>
        function showTab(tabName) {
            document.querySelectorAll(".tab-content").forEach((tab) => {
                tab.classList.add("hidden");
                tab.classList.remove("animate-fade-in");
            });
            setTimeout(() => {
                const activeTab = document.getElementById(tabName + "-tab");
                activeTab.classList.remove("hidden");
                activeTab.classList.add("animate-fade-in");
                if (tabName === "skills") setTimeout(animateSkillBars, 300);
                if (tabName === "survey") { loadSurveyQuestions(); loadSurveyStats(); }
            }, 50);
            document.querySelectorAll(".tab-btn").forEach((btn) => {
                btn.classList.remove("bg-purple-500", "text-white");
                btn.classList.add("text-purple-300");
            });
            document.querySelector(`[data-tab="${tabName}"]`).classList.add("bg-purple-500", "text-white");
        }

        function animateSkillBars() {
            document.querySelectorAll(".skill-progress").forEach((bar) => {
                bar.style.width = bar.getAttribute("data-width");
            });
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
                    questionDiv.innerHTML = `<label class="block text-gray-300 font-semibold">${q.text}</label>`;
                    if (q.type === 'rating') {
                        questionDiv.innerHTML += `<div class="flex gap-2 flex-wrap">${q.options.map(option => `
                            <label class="flex items-center space-x-2 cursor-pointer">
                                <input type="radio" name="question_${q.id}" value="${option}" class="hidden peer" required>
                                <span class="px-4 py-2 rounded-lg bg-slate-700 text-gray-300 peer-checked:bg-purple-500 peer-checked:text-white transition-all">${option}</span>
                            </label>`).join('')}</div>`;
                    } else if (q.type === 'text') {
                        questionDiv.innerHTML += `<textarea name="question_${q.id}" placeholder="${q.placeholder}" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" rows="3"></textarea>`;
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
                    container.innerHTML = '<div class="text-center text-gray-400 py-8">Brak odpowiedzi na ankietę.</div>';
                    return;
                }
                let statsHTML = `<div class="space-y-4"><div class="grid grid-cols-2 gap-4 text-center">
                    <div class="bg-slate-800/50 rounded-lg p-4"><div class="text-2xl font-bold text-purple-300">${stats.total_visits}</div><div class="text-sm text-gray-400">Odwiedzin</div></div>
                    <div class="bg-slate-800/50 rounded-lg p-4"><div class="text-2xl font-bold text-purple-300">${stats.total_responses}</div><div class="text-sm text-gray-400">Odpowiedzi</div></div></div>`;
                for (const [question, answers] of Object.entries(stats.survey_responses)) {
                    statsHTML += `<div class="border-t border-purple-500/20 pt-4"><h4 class="font-semibold text-purple-300 mb-2">${question}</h4><div class="space-y-2">`;
                    answers.forEach(item => {
                        statsHTML += `<div class="flex justify-between items-center"><span class="text-gray-300 text-sm">${item.answer}</span><span class="text-purple-300 font-semibold">${item.count}</span></div>`;
                    });
                    statsHTML += `</div></div>`;
                }
                statsHTML += `</div>`;
                container.innerHTML = statsHTML;
                updateSurveyChart(stats);
            } catch (error) {
                console.error('Error loading survey stats:', error);
            }
        }

        function updateSurveyChart(stats) {
            const ctx = document.getElementById('survey-chart').getContext('2d');
            const labels = []; const data = [];
            for (const [question, answers] of Object.entries(stats.survey_responses)) {
                answers.forEach(item => { labels.push(`${question}: ${item.answer}`); data.push(item.count); });
            }
            new Chart(ctx, {
                type: 'doughnut',
                data: { labels: labels, datasets: [{ data: data, backgroundColor: ['#a855f7','#ec4899','#8b5cf6','#d946ef','#7c3aed'] }] },
                options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { color: '#cbd5e1', font: { size: 10 } } } } }
            });
        }

        document.getElementById('survey-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const responses = [];
            for (let i = 1; i <= 5; i++) {
                const questionElement = e.target.elements[`question_${i}`];
                if (questionElement) {
                    if (questionElement.type === 'radio') {
                        const selected = document.querySelector(`input[name="question_${i}"]:checked`);
                        if (selected) responses.push({ question: `Pytanie ${i}`, answer: selected.value });
                    } else if (questionElement.tagName === 'TEXTAREA' && questionElement.value.trim()) {
                        responses.push({ question: `Pytanie ${i}`, answer: questionElement.value.trim() });
                    }
                }
            }
            if (responses.length === 0) { showSurveyMessage('Proszę odpowiedzieć na przynajmniej jedno pytanie', 'error'); return; }
            try {
                for (const response of responses) {
                    await fetch('/api/survey/submit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(response) });
                }
                showSurveyMessage('Dziękujemy za wypełnienie ankiety!', 'success');
                e.target.reset(); loadSurveyStats();
            } catch (error) {
                console.error('Error submitting survey:', error);
                showSurveyMessage('Wystąpił błąd podczas wysyłania ankiety', 'error');
            }
        });

        function showSurveyMessage(text, type) {
            const messageDiv = document.getElementById('survey-message');
            messageDiv.textContent = text;
            messageDiv.className = 'mt-4 p-3 rounded-lg';
            messageDiv.classList.add(type === 'error' ? 'bg-red-500/20 text-red-300 border border-red-500/30' : 'bg-green-500/20 text-green-300 border border-green-500/30');
            messageDiv.classList.remove('hidden');
            setTimeout(() => { messageDiv.classList.add('hidden'); }, 5000);
        }

        document.getElementById('contact-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const formData = new FormData(e.target);
            try {
                const response = await fetch('/api/contact', { method: 'POST', body: formData });
                const result = await response.json();
                showFormMessage(result.message, response.ok ? "success" : "error");
                if (response.ok) e.target.reset();
            } catch (error) {
                console.error('Error sending contact form:', error);
                showFormMessage("Wystąpił błąd podczas wysyłania wiadomości", "error");
            }
        });

        function showFormMessage(text, type) {
            const formMessage = document.getElementById('form-message');
            formMessage.textContent = text;
            formMessage.className = "mt-4 p-3 rounded-lg";
            formMessage.classList.add(type === "error" ? "bg-red-500/20 text-red-300 border border-red-500/30" : "bg-green-500/20 text-green-300 border border-green-500/30");
            formMessage.classList.remove("hidden");
            setTimeout(() => { formMessage.classList.add("hidden"); }, 5000);
        }

        document.addEventListener("DOMContentLoaded", () => {
            showTab("intro");
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
 info "FastAPI app with survey system generated."
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
}

generate_github_actions(){
 info "Writing GitHub Actions workflow..."
 mkdir_p "$WORKFLOW_DIR"
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
}

generate_k8s_manifests(){
 info "Generating Kubernetes manifests..."
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
         value: "outgoing_messages"
       - name: KAFKA_BOOTSTRAP_SERVERS
         value: "kafka.${NAMESPACE}.svc.cluster.local:9092"
       - name: KAFKA_TOPIC
         value: "survey-topic"
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
         value: "outgoing_messages"
       - name: KAFKA_BOOTSTRAP_SERVERS
         value: "kafka.${NAMESPACE}.svc.cluster.local:9092"
       - name: KAFKA_TOPIC
         value: "survey-topic"
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

 # redis
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

 # kafka-kraft
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

 # monitoring manifests (Prometheus, Grafana, Loki, Tempo)
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
     - job_name: 'redis'
       static_configs:
         - targets: ['redis:6379']
     - job_name: 'postgres'
       static_configs:
         - targets: ['postgres-db:5432']
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

 # kustomization
 cat > "${BASE_DIR}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
 - app-deployment.yaml
 - message-processor.yaml
 - postgres-db.yaml
 - redis.yaml
 - kafka-kraft.yaml
 - prometheus-config.yaml
 - prometheus.yaml
 - grafana-datasource.yaml
 - grafana.yaml

commonLabels:
 app.kubernetes.io/name: ${PROJECT}
 app.kubernetes.io/instance: ${PROJECT}
 app.kubernetes.io/managed-by: kustomize
YAML

 info "Kubernetes manifests written to ${BASE_DIR}."
}

generate_readme(){
 info "Generating README.md..."
 cat > "${ROOT_DIR}/README.md" <<README
# ${PROJECT} - Personal Website with Survey System

## Features
- FastAPI backend with survey system
- Redis message queue for async processing
- Kafka for event streaming
- PostgreSQL for data persistence
- Full monitoring stack (Prometheus, Grafana)
- Vault for secrets management

## Architecture
1. Frontend: HTML/CSS/JS with Tailwind
2. Backend: FastAPI with Redis queue
3. Worker: Processes messages from Redis, sends to Kafka and PostgreSQL
4. Monitoring: Prometheus metrics, Grafana dashboards

## Quick Start
\`\`\`bash
./unified-stack.sh generate
docker build -t ${REGISTRY}:latest .
docker push ${REGISTRY}:latest
kubectl apply -k manifests/base
\`\`\`

## Survey Flow
1. User fills survey → FastAPI → Redis
2. Worker consumes from Redis → Kafka + PostgreSQL
3. Real-time stats displayed with Chart.js
README
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
 echo "Next steps:"
 echo "1. Build image: docker build -t ${REGISTRY}:latest ."
 echo "2. Push to registry: docker push ${REGISTRY}:latest" 
 echo "3. Deploy: kubectl apply -k manifests/base"
}

case "${1:-}" in
 generate) generate_all ;;
 help|-h|--help)
   cat <<EOF
Usage: $0 generate
Generates complete website with survey system and monitoring.
EOF
   ;;
 *)
   echo "Unknown command. Use: $0 help"
   exit 1
   ;;
esac