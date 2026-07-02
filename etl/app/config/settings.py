"""
Production configuration and settings management.
Handles environment variables, validation, and runtime configuration.
Updated for Pydantic v2 / pydantic-settings.
"""

import os
import logging
from functools import lru_cache
from typing import Optional, List

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


logger = logging.getLogger(__name__)


class CloudSettings(BaseSettings):
    """Google Cloud Platform configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    gcp_project_id: str = Field(default="your-project-id", alias="GCP_PROJECT_ID")
    gcp_region: str = Field(default="us-central1", alias="GCP_REGION")
    gcs_bucket: str = Field(default="your-bucket", alias="GCS_BUCKET")
    gcs_upload_folder: str = Field(default="uploads", alias="GCS_UPLOAD_FOLDER")
    bigquery_dataset: str = Field(default="janmat", alias="BIGQUERY_DATASET")
    bigquery_table_grievances: str = Field(default="citizen_grievances", alias="BIGQUERY_TABLE_GRIEVANCES")
    bigquery_table_audit: str = Field(default="pipeline_audit", alias="BIGQUERY_TABLE_AUDIT")
    pubsub_topic_submissions: str = Field(default="grievances", alias="PUBSUB_TOPIC_SUBMISSIONS")
    pubsub_topic_dlq: str = Field(default="grievances-dlq", alias="PUBSUB_TOPIC_DLQ")
    pubsub_subscription: str = Field(default="grievances-sub", alias="PUBSUB_SUBSCRIPTION")


class APISettings(BaseSettings):
    """FastAPI configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    api_title: str = Field(default="JanMat ETL Pipeline", alias="API_TITLE")
    api_version: str = Field(default="1.0.0", alias="API_VERSION")
    api_description: str = Field(default="Production ETL for multimodal citizen input", alias="API_DESCRIPTION")
    host: str = Field(default="0.0.0.0", alias="API_HOST")
    port: int = Field(default=8000, alias="API_PORT")
    debug: bool = Field(default=True, alias="DEBUG")
    workers: int = Field(default=1, alias="WORKERS")
    reload: bool = Field(default=True, alias="RELOAD")
    cors_origins: List[str] = Field(default=["*"], alias="CORS_ORIGINS")

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, v):
        if isinstance(v, str):
            return [x.strip() for x in v.split(",")]
        return v


class FileSettings(BaseSettings):
    """File upload configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    max_file_size_mb: int = Field(default=100, alias="MAX_FILE_SIZE_MB")
    allowed_image_types: List[str] = Field(default=["image/jpeg", "image/png", "image/webp"], alias="ALLOWED_IMAGE_TYPES")
    allowed_audio_types: List[str] = Field(default=["audio/mpeg", "audio/wav", "audio/ogg"], alias="ALLOWED_AUDIO_TYPES")
    allowed_pdf_types: List[str] = Field(default=["application/pdf"], alias="ALLOWED_PDF_TYPES")
    temp_upload_dir: str = Field(default="/tmp/uploads", alias="TEMP_UPLOAD_DIR")

    @field_validator("allowed_image_types", "allowed_audio_types", "allowed_pdf_types", mode="before")
    @classmethod
    def parse_mime_types(cls, v):
        if isinstance(v, str):
            return [x.strip() for x in v.split(",")]
        return v


class AISettings(BaseSettings):
    """AI/Gemini configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    gemini_api_key: str = Field(default="", alias="GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-2.5-flash", alias="GEMINI_MODEL")
    gemini_temperature: float = Field(default=0.3, alias="GEMINI_TEMPERATURE")
    gemini_max_tokens: int = Field(default=1024, alias="GEMINI_MAX_TOKENS")
    ai_timeout_seconds: int = Field(default=30, alias="AI_TIMEOUT_SECONDS")
    ai_retry_attempts: int = Field(default=3, alias="AI_RETRY_ATTEMPTS")
    ai_retry_delay_seconds: int = Field(default=2, alias="AI_RETRY_DELAY_SECONDS")
    confidence_threshold: float = Field(default=0.7, alias="CONFIDENCE_THRESHOLD")


class ProcessingSettings(BaseSettings):
    """ETL processing configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    enable_ocr: bool = Field(default=True, alias="ENABLE_OCR")
    enable_stt: bool = Field(default=True, alias="ENABLE_STT")
    enable_translation: bool = Field(default=True, alias="ENABLE_TRANSLATION")
    language_detection_confidence: float = Field(default=0.6, alias="LANG_DETECT_CONF")
    max_text_length: int = Field(default=10000, alias="MAX_TEXT_LENGTH")
    min_text_length: int = Field(default=10, alias="MIN_TEXT_LENGTH")
    processing_timeout_seconds: int = Field(default=120, alias="PROCESSING_TIMEOUT")


class MonitoringSettings(BaseSettings):
    """Monitoring and logging configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    structured_logging: bool = Field(default=True, alias="STRUCTURED_LOGGING")
    sentry_dsn: Optional[str] = Field(default=None, alias="SENTRY_DSN")
    enable_metrics: bool = Field(default=True, alias="ENABLE_METRICS")
    metrics_port: int = Field(default=8001, alias="METRICS_PORT")


class DatabaseSettings(BaseSettings):
    """Database configuration."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    bigquery_credentials_path: Optional[str] = Field(default=None, alias="BIGQUERY_CREDENTIALS_PATH")
    bigquery_location: str = Field(default="US", alias="BIGQUERY_LOCATION")
    bigquery_timeout_seconds: int = Field(default=30, alias="BQ_TIMEOUT_SECONDS")


class Settings(BaseSettings):
    """Master settings aggregator."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    environment: str = Field(default="development", alias="ENVIRONMENT")
    is_production: bool = Field(default=False, alias="IS_PRODUCTION")

    # Sub-settings (instantiated directly — each reads from .env independently)
    cloud: CloudSettings = CloudSettings()
    api: APISettings = APISettings()
    files: FileSettings = FileSettings()
    ai: AISettings = AISettings()
    processing: ProcessingSettings = ProcessingSettings()
    monitoring: MonitoringSettings = MonitoringSettings()
    database: DatabaseSettings = DatabaseSettings()


@lru_cache()
def get_settings() -> Settings:
    """
    Cached settings singleton.
    Returns the same Settings instance across the application.
    """
    return Settings()


def validate_settings() -> bool:
    """Validate all settings at startup. In dev mode, skips strict GCP checks."""
    try:
        settings = get_settings()

        # In development, these can be placeholders
        if settings.environment == "production":
            if not settings.cloud.gcp_project_id or settings.cloud.gcp_project_id == "your-project-id":
                raise ValueError("GCP_PROJECT_ID not configured for production")
            if not settings.cloud.gcs_bucket or settings.cloud.gcs_bucket == "your-bucket":
                raise ValueError("GCS_BUCKET not configured for production")
            if not settings.ai.gemini_api_key:
                raise ValueError("GEMINI_API_KEY not configured for production")

        # Validate numeric ranges
        if not (0.0 <= settings.ai.gemini_temperature <= 1.0):
            raise ValueError("gemini_temperature must be between 0 and 1")
        if not (0.0 <= settings.ai.confidence_threshold <= 1.0):
            raise ValueError("confidence_threshold must be between 0 and 1")
        if settings.files.max_file_size_mb <= 0:
            raise ValueError("max_file_size_mb must be positive")

        logger.info("✓ All settings validated successfully")
        return True

    except Exception as e:
        logger.error(f"✗ Settings validation failed: {str(e)}")
        raise


if __name__ == "__main__":
    settings = get_settings()
    print("✓ Settings loaded successfully")
    print(f"  Environment: {settings.environment}")
    print(f"  GCP Project: {settings.cloud.gcp_project_id}")
    print(f"  API Port:    {settings.api.port}")
