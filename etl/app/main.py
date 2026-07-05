"""
Main FastAPI application.
Entry point for the production ETL pipeline API.
"""

import sys
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
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
    logger.info(
        f"  Total errors: {
            sum(
                [
                    metrics.metrics.get('validation_failures', 0),
                    metrics.metrics.get('extraction_failures', 0),
                    metrics.metrics.get('ai_api_failures', 0),
                    metrics.metrics.get('bigquery_insert_failures', 0),
                ]
            )
        }"
    )


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
        import uuid

        request_id = str(uuid.uuid4())

    # Store in request state for access in routes
    request.state.request_id = request_id

    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


@app.exception_handler(PipelineException)
async def pipeline_exception_handler(request: Request, exc: PipelineException):
    """Handle PipelineException."""

    request_id = getattr(request.state, "request_id", None)

    # Log the exception
    audit_logger.log_error(
        request_id=request_id or "unknown",
        stage=exc.stage or "unknown",
        error_code=exc.error_code.value,
        message=exc.message,
    )

    # Determine HTTP status code
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


# Health check endpoints
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
    """Readiness check - verify all dependencies."""

    try:
        # Quick checks of all services
        from app.storage.gcs_client import get_gcs_client
        from app.database.bigquery_client import get_bigquery_client
        from app.queue.pubsub_client import get_pubsub_client

        # These will raise exceptions if clients can't be initialized
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


# Register routes
def register_routes():
    """Register API routes."""

    # Will be implemented in app/api/routes/ modules
    # For now, include stub implementations

    @app.post("/api/v1/submit/text")
    async def submit_text(request: Request, body: dict):
        """Submit text for analysis."""
        request_id = request.state.request_id
        logger.info(f"Text submission received: {request_id}")
        return {
            "request_id": request_id,
            "status": "accepted",
            "message": "Submission queued for processing",
        }

    @app.post("/api/v1/submit/image")
    async def submit_image(request: Request):
        """Submit image for analysis."""
        request_id = request.state.request_id
        logger.info(f"Image submission received: {request_id}")
        return {"request_id": request_id, "status": "accepted"}

    @app.post("/api/v1/submit/audio")
    async def submit_audio(request: Request):
        """Submit audio for analysis."""
        request_id = request.state.request_id
        logger.info(f"Audio submission received: {request_id}")
        return {"request_id": request_id, "status": "accepted"}

    @app.post("/api/v1/submit/pdf")
    async def submit_pdf(request: Request):
        """Submit PDF for analysis."""
        request_id = request.state.request_id
        logger.info(f"PDF submission received: {request_id}")
        return {"request_id": request_id, "status": "accepted"}

    @app.get("/api/v1/submissions/{request_id}")
    async def get_submission_status(request_id: str):
        """Get submission status."""
        return {
            "request_id": request_id,
            "status": "processing",
            "progress_percent": 50,
        }


# Pub/Sub push endpoint — receives messages from grievance-processor-push-sub
@app.post("/api/v1/pubsub/push")
async def pubsub_push(request: Request):
    """
    Receives Pub/Sub push messages from the grievance-submitted topic.
    Payload is a standard Pub/Sub push message:
      { "message": { "data": "<base64>", "messageId": "...", "attributes": {...} },
        "subscription": "projects/.../subscriptions/..." }
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
        f"Pub/Sub push received: submission_id={submission_id} "
        f"type={input_type} constituency={constituency_id}",
        request_id=request_id,
    )
    audit_logger.log_error(
        request_id=request_id,
        stage="pubsub_push",
        error_code="INFO",
        message=f"Received submission {submission_id} for ETL processing",
    )

    # TODO: invoke the full ETL pipeline for this submission
    # For now acknowledge receipt — further processing is added iteratively
    return {"status": "received", "submission_id": submission_id, "request_id": request_id}


# Register routes on startup
register_routes()


def create_app() -> FastAPI:
    """Create and configure FastAPI application."""
    return app


if __name__ == "__main__":
    # Run with: python -m app.main

    uvicorn.run(
        "app.main:app",
        host=settings.api.host,
        port=settings.api.port,
        workers=settings.api.workers,
        reload=settings.api.reload,
        log_level=settings.monitoring.log_level.lower(),
    )
