# ── Build stage ──────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build dependencies for asyncpg / cryptography
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Copy installed packages from build stage
COPY --from=builder /install /usr/local

# Non-root user for security
RUN adduser --disabled-password --gecos '' --uid 1000 appuser
USER appuser

# Copy application code (build context = project root, not backend/)
# Run: gcloud builds submit --tag ... --source . from JanMat/ root
COPY --chown=appuser:appuser backend/app/ ./app/
# BigQuery SQL queries loaded at runtime by bigquery.py
COPY --chown=appuser:appuser bigquery/queries/ ./bigquery/queries/

# Cloud Run expects PORT env var; default to 8080
ENV PORT=8080 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--log-config", "/dev/null"]
