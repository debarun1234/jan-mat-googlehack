"""
JanMat Backend — FastAPI Application Entrypoint

Three-phase pipeline:
  Phase 1 (intake)     — citizen submission ingestion
  Phase 2 (analytics)  — BigQuery clustering + priority scoring
  Phase 3 (dashboard)  — MP executive dashboard API
"""
import structlog
import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.routers import analytics, dashboard, intake, users

# ── Structured logging for Cloud Logging ──────────────────────────────
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    logger_factory=structlog.PrintLoggerFactory(sys.stdout),
)

log = structlog.get_logger()


# ── Lifespan ──────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    log.info(
        "janmat_startup",
        project=settings.gcp_project_id,
        region=settings.gcp_region,
        gemini_model=settings.gemini_model,
        constituency_id=settings.constituency_id,
    )
    yield
    log.info("janmat_shutdown")


# ── App factory ───────────────────────────────────────────────────────

def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title="JanMat API",
        description=(
            "People's Priority Engine — AI-driven constituency development planning for MPs. "
            "Three-phase pipeline: citizen ingestion → BigQuery analytics → MP dashboard."
        ),
        version="1.0.0",
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # CORS — allow Flutter app + Node.js dashboard
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── Routers ──────────────────────────────────────────────────────
    app.include_router(intake.router)
    app.include_router(analytics.router)
    app.include_router(dashboard.router)
    app.include_router(users.router)

    # ── Health check ─────────────────────────────────────────────────
    @app.get("/health", tags=["infra"])
    async def health():
        """Cloud Run liveness + startup probe target."""
        return {"status": "ok", "service": "janmat-backend"}

    @app.get("/", tags=["infra"])
    async def root():
        return {
            "service": "JanMat API",
            "version": "1.0.0",
            "docs": "/docs",
            "phases": {
                "1_intake": "/intake — citizen submission (text, audio, image)",
                "2_analytics": "/analytics — demand clustering + priority scoring",
                "3_dashboard": "/dashboard — MP ranked project list + evidence",
            },
        }

    # ── Global exception handler ─────────────────────────────────────
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        log.error(
            "unhandled_exception",
            path=request.url.path,
            method=request.method,
            error=str(exc),
            error_type=type(exc).__name__,
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"detail": "Internal server error", "type": type(exc).__name__},
        )

    return app


app = create_app()
