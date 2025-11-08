#!/usr/bin/env python3
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
import os, json, time, logging
import redis
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi")

app = FastAPI(title="Personal Website")
templates = Jinja2Templates(directory="templates")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

REDIS_HOST = os.getenv("REDIS_HOST","redis")
REDIS_PORT = int(os.getenv("REDIS_PORT","6379"))
REDIS_LIST = os.getenv("REDIS_LIST","outgoing_messages")

CONTACT_PUSHED = Counter("app_contact_pushed_total","Contact messages queued")

def redis_client():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

Instrumentator().instrument(app).expose(app)

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/api/contact")
async def contact(email: str = Form(...), message: str = Form(...), id: str = Form(default="")):
    payload = {"id": id, "email": email, "message": message, "ts": time.time()}
    try:
        r = redis_client()
        r.rpush(REDIS_LIST, json.dumps(payload))
        CONTACT_PUSHED.inc()
        logger.info("Queued: %s", payload)
        return {"status":"queued", "payload": payload}
    except Exception as e:
        logger.exception("Failed to enqueue")
        raise HTTPException(status_code=500, detail="queue error")

@app.get("/health")
async def health():
    try:
        redis_client().ping()
        return {"status":"ok","redis":"connected"}
    except Exception as e:
        return {"status":"degraded","redis":"disconnected","error": str(e)}
