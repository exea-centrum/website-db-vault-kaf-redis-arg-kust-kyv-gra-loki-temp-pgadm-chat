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
