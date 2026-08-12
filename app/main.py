"""FastAPI RAG service — retrieval-augmented Bible Q&A on the platform.

Retrieval runs against pgvector in Cloud SQL (app/rag.py); generation streams
from the Claude API (app/llm.py). Instrumented with RED-method Prometheus
metrics so it is scraped by the in-cluster Prometheus (k8s/monitoring).
"""

import os
import time

from fastapi import Depends, FastAPI, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from llm import chat_stream
from rag import SessionLocal, search

RELEVANCE_THRESHOLD = float(os.getenv("RELEVANCE_THRESHOLD", "1.0"))
HISTORY_WINDOW = int(os.getenv("HISTORY_WINDOW", "6"))

app = FastAPI(title="Pocket Preacher — RAG Service")

# Frontend origin is environment-specific; unset means no cross-origin browser access.
_cors_origin = os.getenv("FRONTEND_ORIGIN")
if _cors_origin:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[_cors_origin],
        allow_methods=["*"],
        allow_headers=["*"],
    )

# --- Prometheus metrics (RED method) ---
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
REQUESTS_IN_PROGRESS = Gauge(
    "http_requests_in_progress",
    "HTTP requests currently being processed",
    ["method", "endpoint"],
)


@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    method = request.method
    path = request.url.path

    if path == "/metrics":
        return await call_next(request)

    # Resolve the route template (e.g. /items/{id}) to avoid label cardinality explosion.
    endpoint = path
    for route in app.routes:
        if hasattr(route, "path") and hasattr(route, "methods"):
            if method in route.methods:
                match, _ = route.matches({"type": "http", "method": method, "path": path})
                if match.value == 2:  # FULL match
                    endpoint = route.path
                    break

    REQUESTS_IN_PROGRESS.labels(method=method, endpoint=endpoint).inc()
    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=500).inc()
        raise
    finally:
        duration = time.perf_counter() - start
        REQUESTS_IN_PROGRESS.labels(method=method, endpoint=endpoint).dec()
        REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(duration)

    REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=response.status_code).inc()
    return response


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/health")
def health():
    """Liveness probe — is the process running?"""
    return {"status": "healthy"}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    """Readiness probe — can we reach the database?"""
    try:
        db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "connected"}
    except Exception:
        return Response(status_code=503)


@app.get("/status")
def status():
    return {
        "app": "pocket-preacher-rag",
        "version": "1.0.0",
        "environment": os.getenv("ENVIRONMENT", "development"),
    }


class HistoryMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    history: list[HistoryMessage] = []


@app.get("/api/search")
def search_verses(
    q: str = Query(..., description="Search query"),
    top_k: int = Query(8, ge=1, le=20),
):
    """Raw vector search — returns relevant passages without LLM generation."""
    return {"query": q, "results": search(q, top_k=top_k)}


@app.post("/api/chat")
def chat(req: ChatRequest):
    """RAG chat — retrieves passages from pgvector, then streams a Claude answer."""
    passages = search(req.message)
    relevant = [p for p in passages if p["distance"] <= RELEVANCE_THRESHOLD]
    history = [
        {"role": m.role, "content": m.content}
        for m in req.history[-HISTORY_WINDOW:]
    ]

    if not relevant:
        async def fallback():
            yield (
                "Hmm, I'm not finding anything about that in Scripture! "
                "I'm a Bible guide — try asking me about verses, stories, or teachings."
            )
        return StreamingResponse(fallback(), media_type="text/plain")

    async def generate():
        async for chunk in chat_stream(req.message, relevant, history):
            yield chunk

    return StreamingResponse(generate(), media_type="text/plain")
