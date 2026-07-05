"""
Main FastAPI application.
Entry point for the production ETL pipeline API.
"""

import sys
import uuid
import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uvicorn

from app.config.settings import get_settings, validate_settings
from app.monitoring.logger import get_logger, get_audit_logger, get_metrics_collector
from app.utils.errors import PipelineException, ErrorCode


# Configure logging before anything else
logger = get_logger(__name__)
audit_logger = get_audit_logger()
metrics = get_metrics_collector()

# Global settings
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic."""

    # Startup
    logger.info("🚀 Starting JanMat ETL Pipeline")

    try:
        validate_settings()
        logger.info("✓ Configuration validated")
        logger.info(f"  Environment: {settings.environment}")
        logger.info(f"  GCP Project: {settings.cloud.gcp_project_id}")
        logger.info(f"  API running on {settings.api.host}:{settings.api.port}")
    except Exception as e:
        logger.critical(f"Configuration validation failed: {str(e)}")
        sys.exit(1)

    yield  # Application runs here

    # Shutdown
    logger.info("⏹️  Shutting down JanMat ETL Pipeline")
    logger.info(
        f"  Total requests processed: {metrics.metrics.get('uploaded_files_total', 0)}"
    )
    error_total = sum(
        [
            metrics.metrics.get("validation_failures", 0),
            metrics.metrics.get("extraction_failures", 0),
            metrics.metrics.get("ai_api_failures", 0),
            metrics.metrics.get("bigquery_insert_failures", 0),
        ]
    )
    logger.info(f"  Total errors: {error_total}")


# Create FastAPI app
app = FastAPI(
    title=settings.api.api_title,
    description=settings.api.api_description,
    version=settings.api.api_version,
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)


# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.api.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_request_id_middleware(request: Request, call_next):
    """Add request ID to all requests."""

    request_id = request.headers.get("X-Request-ID")
    if not request_id:
        request_id = str(uuid.uuid4())

    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


@app.exception_handler(PipelineException)
async def pipeline_exception_handler(request: Request, exc: PipelineException):
    """Handle PipelineException."""

    request_id = getattr(request.state, "request_id", None)

    audit_logger.log_error(
        request_id=request_id or "unknown",
        stage=exc.stage or "unknown",
        error_code=exc.error_code.value,
        message=exc.message,
    )

    if exc.error_code in {
        ErrorCode.INVALID_FILE_TYPE,
        ErrorCode.FILE_TOO_LARGE,
        ErrorCode.FILE_TOO_SMALL,
        ErrorCode.MISSING_REQUIRED_FIELD,
        ErrorCode.MALFORMED_REQUEST,
    }:
        status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    elif exc.error_code in {
        ErrorCode.GCS_PERMISSION_DENIED,
        ErrorCode.BIGQUERY_PERMISSION_DENIED,
    }:
        status_code = status.HTTP_403_FORBIDDEN
    elif exc.error_code in {
        ErrorCode.GCS_QUOTA_EXCEEDED,
        ErrorCode.BIGQUERY_QUOTA_EXCEEDED,
        ErrorCode.AI_QUOTA_EXCEEDED,
    }:
        status_code = status.HTTP_429_TOO_MANY_REQUESTS
    elif exc.error_code in {
        ErrorCode.SERVICE_UNAVAILABLE,
        ErrorCode.GCS_UPLOAD_FAILED,
        ErrorCode.BIGQUERY_INSERT_FAILED,
    }:
        status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    else:
        status_code = status.HTTP_500_INTERNAL_SERVER_ERROR

    return JSONResponse(
        status_code=status_code,
        content={
            "error_code": exc.error_code.value,
            "message": exc.message,
            "request_id": request_id,
            "details": exc.details,
        },
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle unexpected exceptions."""

    request_id = getattr(request.state, "request_id", None)

    logger.error(
        f"Unexpected error: {str(exc)}",
        request_id=request_id,
        error_type=type(exc).__name__,
    )

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error_code": "INTERNAL_SERVER_ERROR",
            "message": "An unexpected error occurred",
            "request_id": request_id,
            "details": {} if settings.api.debug else None,
        },
    )


# ── Health / readiness / metrics ──────────────────────────────────────────────


@app.get("/health")
async def health_check():
    """Basic health check."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": settings.api.api_version,
    }


@app.get("/ready")
async def readiness_check():
    """Readiness check — verify all GCP dependencies are reachable."""
    try:
        from app.storage.gcs_client import get_gcs_client
        from app.database.bigquery_client import get_bigquery_client
        from app.queue.pubsub_client import get_pubsub_client

        get_gcs_client()
        get_bigquery_client()
        get_pubsub_client()

        return {
            "ready": True,
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {"gcs": "ok", "bigquery": "ok", "pubsub": "ok"},
        }
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "ready": False,
                "timestamp": datetime.utcnow().isoformat(),
                "error": str(e),
            },
        )


@app.get("/metrics")
async def get_metrics():
    """Get application metrics."""
    return {**metrics.get_metrics(), "timestamp": datetime.utcnow().isoformat()}


# ── Request/Response models ───────────────────────────────────────────────────


class ProcessRequest(BaseModel):
    """
    Direct text processing request.
    Classifies a grievance text via Gemini and stores the result to BigQuery.
    """

    text: str = Field(
        ..., min_length=5, description="Citizen grievance text to classify"
    )
    submission_id: Optional[str] = Field(
        None, description="Submission ID (auto-generated if omitted)"
    )
    constituency_id: str = Field(default="KA-BLR-NORTH-01")
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    input_type: str = Field(default="text")
    language: str = Field(default="en")


class ProcessResponse(BaseModel):
    submission_id: str
    status: str
    category: Optional[str] = None
    priority: Optional[str] = None
    sentiment: Optional[str] = None
    summary_en: Optional[str] = None
    confidence_score: Optional[float] = None
    stored_to_bigquery: bool = False
    processing_time_ms: Optional[int] = None


# ── Core pipeline (sync — runs in thread pool) ────────────────────────────────


def _run_pipeline_sync(
    text: str,
    submission_id: str,
    constituency_id: str,
    input_type: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    gcs_uri: str = "",
) -> dict:
    """
    Synchronous ETL pipeline for a single text submission.

    Runs inside a thread pool executor so GeminiClient.infer() — which calls
    asyncio.run() internally — can create its own event loop without conflicting
    with FastAPI's running loop.

    Steps:
      1. Gemini classification (category / priority / sentiment / summary)
      2. BigQuery insert into citizen_grievances

    Returns a result dict consumed by ProcessResponse.
    """
    import time as _time

    start = _time.monotonic()
    result: dict = {
        "submission_id": submission_id,
        "status": "failed",
        "stored_to_bigquery": False,
    }
    ai_result: dict = {}

    # ── Step 1: Gemini classification ─────────────────────────────────────────
    try:
        from app.ai_engine.gemini_client import GeminiClient

        client = GeminiClient()
        ai_result = client.infer(text, request_id=submission_id)
        result.update(
            {
                "category": ai_result.get("category"),
                "priority": ai_result.get("priority"),
                "sentiment": ai_result.get("sentiment"),
                "summary_en": ai_result.get("summary_en"),
                "confidence_score": ai_result.get("confidence_score"),
            }
        )
        metrics.increment("ai_api_calls_total")
        logger.info(
            f"Gemini classified {submission_id}: "
            f"category={ai_result.get('category')} priority={ai_result.get('priority')}",
            request_id=submission_id,
        )
    except Exception as e:
        metrics.increment("ai_api_failures")
        logger.error(
            f"Gemini classification failed for {submission_id}: {e}",
            request_id=submission_id,
        )
        result["status"] = "ai_failed"
        result["processing_time_ms"] = int((_time.monotonic() - start) * 1000)
        return result

    # ── Step 2: BigQuery insert ───────────────────────────────────────────────
    try:
        from app.database.bigquery_client import BigQueryClient

        bq = BigQueryClient()
        now = datetime.now(timezone.utc).isoformat()
        row = {
            "submission_id": submission_id,
            "gcs_uri": gcs_uri
            or f"gs://{settings.cloud.gcs_bucket}/etl/{submission_id}",
            "input_type": input_type,
            "raw_text": text[:5000],
            "category": ai_result.get("category", "Other"),
            "priority": ai_result.get("priority"),
            "sentiment": ai_result.get("sentiment"),
            "summary_en": ai_result.get("summary_en", ""),
            "confidence_score": float(ai_result.get("confidence_score", 0.0)),
            "latitude": latitude,
            "longitude": longitude,
            "hotspot_id": None,
            "priority_score": None,
            "evidence_log": None,
            "submitted_at": now,
            "processing_completed_at": now,
            "pipeline_version": settings.api.api_version,
        }
        bq.insert_rows(
            table_name=settings.cloud.bigquery_table_grievances,
            rows=[row],
            request_id=submission_id,
            fail_on_duplicate=False,
        )
        result["stored_to_bigquery"] = True
        metrics.increment("bigquery_inserts_total")
        logger.info(f"BigQuery insert OK for {submission_id}", request_id=submission_id)
    except Exception as e:
        metrics.increment("bigquery_insert_failures")
        logger.error(
            f"BigQuery insert failed for {submission_id}: {e}",
            request_id=submission_id,
        )
        # Classification succeeded — partial success is still useful to the caller

    result["status"] = "completed"
    result["processing_time_ms"] = int((_time.monotonic() - start) * 1000)
    metrics.increment("uploaded_files_total")
    return result


# ── API endpoints ─────────────────────────────────────────────────────────────


@app.post("/api/v1/pipeline/process", response_model=ProcessResponse)
async def pipeline_process(body: ProcessRequest, request: Request):
    """
    Classify a grievance text via Gemini and persist the result to BigQuery.

    This is the direct HTTP entry point into the ETL pipeline — used by the
    MP dashboard for test submissions and by the citizen app as an alternative
    to the backend /intake/text route.

    The heavy Gemini call runs in a thread pool so asyncio.run() inside
    GeminiClient.infer() can safely create its own event loop.
    """
    request_id = request.state.request_id
    submission_id = body.submission_id or f"etl-{uuid.uuid4().hex[:12]}"
    logger.info(
        f"Pipeline process request: submission_id={submission_id} type={body.input_type}",
        request_id=request_id,
    )
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None,
        lambda: _run_pipeline_sync(
            text=body.text,
            submission_id=submission_id,
            constituency_id=body.constituency_id,
            input_type=body.input_type,
            latitude=body.latitude,
            longitude=body.longitude,
        ),
    )
    return ProcessResponse(**result)


@app.get("/api/v1/pipeline/stats")
async def pipeline_stats(constituency_id: str = "KA-BLR-NORTH-01"):
    """
    Return submission counts grouped by category from BigQuery.
    Called by the MP dashboard to populate the telemetry view.
    """
    try:
        from google.cloud import bigquery as bq_lib

        client = bq_lib.Client(project=settings.cloud.gcp_project_id)
        dataset = settings.cloud.bigquery_dataset
        table = settings.cloud.bigquery_table_grievances
        query = (
            f"SELECT category, COUNT(*) AS count, AVG(confidence_score) AS avg_confidence "
            f"FROM `{settings.cloud.gcp_project_id}.{dataset}.{table}` "
            f"GROUP BY category ORDER BY count DESC LIMIT 20"
        )
        rows = list(client.query(query).result())
        categories = [
            {
                "category": row.category,
                "count": row.count,
                "avg_confidence": round(row.avg_confidence or 0, 3),
            }
            for row in rows
        ]
        total = sum(c["count"] for c in categories)
        return {
            "total_submissions": total,
            "by_category": categories,
            "constituency_id": constituency_id,
            "queried_at": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as e:
        logger.error(f"BigQuery stats query failed: {e}")
        return {
            "total_submissions": 0,
            "by_category": [],
            "constituency_id": constituency_id,
            "error": str(e),
            "queried_at": datetime.now(timezone.utc).isoformat(),
        }


# ── Pub/Sub push endpoint ─────────────────────────────────────────────────────


@app.post("/api/v1/pubsub/push")
async def pubsub_push(request: Request):
    """
    Receives Pub/Sub push messages from the grievance-submitted topic.

    The backend publishes {submission_id, constituency_id, input_type} after
    inserting a grievance record to BigQuery. The ETL acknowledges each message
    so Pub/Sub does not retry, and logs the event for audit purposes.

    Pub/Sub push payload:
      { "message": { "data": "<base64-json>", "messageId": "...", "attributes": {...} },
        "subscription": "projects/.../subscriptions/..." }

    Returning any 2xx status acknowledges the message. Non-2xx triggers a retry.
    """
    import base64
    import json as _json

    body = await request.json()
    msg = body.get("message", {})
    raw = msg.get("data", "")
    request_id = request.state.request_id

    try:
        payload = _json.loads(base64.b64decode(raw).decode("utf-8")) if raw else {}
    except Exception:
        payload = {}

    submission_id = payload.get("submission_id", "unknown")
    input_type = payload.get("input_type", "unknown")
    constituency_id = payload.get("constituency_id", "unknown")

    logger.info(
        f"Pub/Sub push: submission_id={submission_id} type={input_type} "
        f"constituency={constituency_id}",
        request_id=request_id,
    )
    audit_logger.log_error(
        request_id=request_id,
        stage="pubsub_push",
        error_code="INFO",
        message=f"Acknowledged submission {submission_id} ({input_type}) for {constituency_id}",
    )
    metrics.increment("uploaded_files_total")

    return {
        "status": "acknowledged",
        "submission_id": submission_id,
        "request_id": request_id,
    }


def create_app() -> FastAPI:
    """Create and configure FastAPI application (used by gunicorn/tests)."""
    return app


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.api.host,
        port=settings.api.port,
        workers=settings.api.workers,
        reload=settings.api.reload,
        log_level=settings.monitoring.log_level.lower(),
    )
