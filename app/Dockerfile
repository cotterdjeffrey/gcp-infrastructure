# Stage 1: Build dependencies in a full Python image
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Minimal runtime image
FROM python:3.12-slim

# Non-root user — containers should never run as root
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

WORKDIR /app
COPY --from=builder /install /usr/local
COPY main.py .

# Switch to non-root user
USER appuser

EXPOSE 8080

# Uvicorn with sensible production defaults
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
