"""
Central configuration — reads from environment variables injected by Cloud Run.
All secrets come from Secret Manager (mounted as env vars via Terraform cloudrun.tf).
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # GCP
    gcp_project_id: str
    gcp_region: str = "asia-south1"

    # Gemini / Vertex AI
    gemini_model: str = "gemini-3.1-flash-lite"   # Vertex AI via google-genai SDK
    # Gemini models are served from us-central1 globally; infra stays in asia-south1
    gemini_region: str = "us-central1"

    # Cloud SQL (injected as DATABASE_URL from Secret Manager)
    database_url: str  # postgresql+asyncpg://user:pass@host/db

    # GCS
    gcs_media_bucket: str

    # Pub/Sub topics
    pubsub_topic_grievance_submitted: str = "grievance-submitted"
    pubsub_topic_processing_complete: str = "processing-complete"
    pubsub_topic_priority_updated: str = "priority-updated"

    # BigQuery
    bq_analytics_dataset: str = "janmat_analytics"
    bq_infrastructure_dataset: str = "janmat_infrastructure"

    # Auth
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 480  # 8 hours
    # Shared key between dashboard (Node.js) and backend to authenticate
    # service-to-service JWT issuance. Override via JANMAT_DASHBOARD_KEY env var.
    janmat_dashboard_key: str = "JanMat-Dashboard-2025"

    # ETL service — backend can forward submissions for deeper processing
    janmat_etl_url: str = ""  # e.g. https://janmat-etl-xxx.a.run.app

    # App
    constituency_id: str = "KA-BLR-NORTH-01"
    cors_origins: list[str] = ["*"]
    log_level: str = "INFO"

    # Demo mode — skips all GCP calls, returns mock data for local testing
    demo_mode: bool = False


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
