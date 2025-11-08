#!/usr/bin/env python3
import os, json, time, logging
import redis
from kafka import KafkaProducer
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST = os.getenv("REDIS_HOST","redis")
REDIS_PORT = int(os.getenv("REDIS_PORT","6379"))
REDIS_LIST = os.getenv("REDIS_LIST","outgoing_messages")

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS","kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC","survey-topic")
DATABASE_URL = os.getenv("DATABASE_URL","dbname=webdb user=webuser password=testpassword host=postgres-db")

def redis_client():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def kafka_producer():
    try:
        return KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP.split(','), value_serializer=lambda v: json.dumps(v).encode('utf-8'))
    except Exception:
        logger.exception("Kafka init failed")
        return None

def save_to_db(email, message):
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    cur.execute("INSERT INTO contact_messages (email,message) VALUES (%s,%s)", (email, message))
    conn.commit()
    cur.close()
    conn.close()

def process(item, producer):
    try:
        if producer:
            producer.send(KAFKA_TOPIC, value=item)
            producer.flush()
        save_to_db(item.get("email"), item.get("message"))
        logger.info("Processed: %s", item.get("email"))
    except Exception:
        logger.exception("Processing failed")

def main():
    r = redis_client()
    producer = kafka_producer()
    logger.info("Worker started")
    while True:
        try:
            res = r.blpop(REDIS_LIST, timeout=0)
            if res:
                _, raw = res
                try:
                    item = json.loads(raw)
                except Exception:
                    item = {"raw": raw}
                process(item, producer)
        except Exception:
            logger.exception("Worker loop error")
            time.sleep(2)

if __name__ == "__main__":
    main()
