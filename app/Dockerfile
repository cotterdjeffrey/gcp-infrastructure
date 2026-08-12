# Stage 1: Build dependencies in a full Python image
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Minimal runtime image
FROM python:3.12-slim

# Bake the embedding model into the image so the pod needs no network egress to
# load it at runtime (the app namespace only allows egress to Cloud SQL + DNS).
ENV SENTENCE_TRANSFORMERS_HOME=/opt/models \
    HF_HOME=/opt/models

# Non-root user — containers should never run as root
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

WORKDIR /app
COPY --from=builder /install /usr/local

# Download the embedding model at build time, then make it world-readable so the
# non-root user can load it from the read-only root filesystem.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')" \
    && chmod -R a+rX /opt/models

COPY main.py rag.py llm.py ingest.py ./

# Switch to non-root user
USER appuser

EXPOSE 8080

# Uvicorn with sensible production defaults
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
