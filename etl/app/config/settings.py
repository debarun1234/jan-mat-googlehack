"""
Production configuration and settings management.
Handles environment variables, validation, and runtime configuration.
"""

import os
from functools import lru_cache
from typing import Optional, List
from pydantic import BaseSettings, Field, validator, AnyHttpUrl
import logging


logger = logging.getLogger(__name__)


class CloudSettings(BaseSettings):
    """Google Cloud Platform configuration."""
    
    gcp_project_id: str = Field(..., env="GCP_PROJECT_ID")
    gcp_region: str = Field(default="us-central1", env="GCP_REGION")
    gcs_bucket: str = Field(..., env="GCS_BUCKET")
    gcs_upload_folder: str = Field(default="uploads", env="GCS_UPLOAD_FOLDER")
    bigquery_dataset: str = Field(..., env="BIGQUERY_DATASET")
    bigquery_table_grievances: str = Field(
        default="citizen_grievances", 
        env="BIGQUERY_TABLE_GRIEVANCES"
    )
    bigquery_table_audit: str = Field(
        default="pipeline_audit",
        env="BIGQUERY_TABLE_AUDIT"
    )
    pubsub_topic_submissions: str = Field(
        ..., env="PUBSUB_TOPIC_SUBMISSIONS"
    )
    pubsub_topic_dlq: str = Field(..., env="PUBSUB_TOPIC_DLQ")
    pubsub_subscription: str = Field(..., env="PUBSUB_SUBSCRIPTION")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class APISettings(BaseSettings):
    """FastAPI configuration."""
    
    api_title: str = Field(default="JanMat ETL Pipeline", env="API_TITLE")
    api_version: str = Field(default="1.0.0", env="API_VERSION")
    api_description: str = Field(
        default="Production ETL for multimodal citizen input",
        env="API_DESCRIPTION"
    )
    host: str = Field(default="0.0.0.0", env="API_HOST")
    port: int = Field(default=8000, env="API_PORT")
    debug: bool = Field(default=False, env="DEBUG")
    workers: int = Field(default=4, env="WORKERS")
    reload: bool = Field(default=False, env="RELOAD")
    cors_origins: List[str] = Field(
        default=["*"],
        env="CORS_ORIGINS"
    )
    
    @validator("cors_origins", pre=True)
    def parse_cors_origins(cls, v):
        if isinstance(v, str):
            return [x.strip() for x in v.split(",")]
        return v
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class FileSettings(BaseSettings):
    """File upload configuration."""
    
    max_file_size_mb: int = Field(default=100, env="MAX_FILE_SIZE_MB")
    allowed_image_types: List[str] = Field(
        default=["image/jpeg", "image/png", "image/webp"],
        env="ALLOWED_IMAGE_TYPES"
    )
    allowed_audio_types: List[str] = Field(
        default=["audio/mpeg", "audio/wav", "audio/ogg"],
        env="ALLOWED_AUDIO_TYPES"
    )
    allowed_pdf_types: List[str] = Field(
        default=["application/pdf"],
        env="ALLOWED_PDF_TYPES"
    )
    temp_upload_dir: str = Field(default="/tmp/uploads", env="TEMP_UPLOAD_DIR")
    
    @validator("allowed_image_types", "allowed_audio_types", "allowed_pdf_types", pre=True)
    def parse_mime_types(cls, v):
        if isinstance(v, str):
            return [x.strip() for x in v.split(",")]
        return v
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class AISettings(BaseSettings):
    """AI/Gemini configuration."""
    
    gemini_api_key: str = Field(..., env="GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-2.5-flash", env="GEMINI_MODEL")
    gemini_temperature: float = Field(default=0.3, env="GEMINI_TEMPERATURE")
    gemini_max_tokens: int = Field(default=1024, env="GEMINI_MAX_TOKENS")
    ai_timeout_seconds: int = Field(default=30, env="AI_TIMEOUT_SECONDS")
    ai_retry_attempts: int = Field(default=3, env="AI_RETRY_ATTEMPTS")
    ai_retry_delay_seconds: int = Field(default=2, env="AI_RETRY_DELAY_SECONDS")
    confidence_threshold: float = Field(default=0.7, env="CONFIDENCE_THRESHOLD")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class ProcessingSettings(BaseSettings):
    """ETL processing configuration."""
    
    enable_ocr: bool = Field(default=True, env="ENABLE_OCR")
    enable_stt: bool = Field(default=True, env="ENABLE_STT")
    enable_translation: bool = Field(default=True, env="ENABLE_TRANSLATION")
    language_detection_confidence: float = Field(default=0.6, env="LANG_DETECT_CONF")
    max_text_length: int = Field(default=10000, env="MAX_TEXT_LENGTH")
    min_text_length: int = Field(default=10, env="MIN_TEXT_LENGTH")
    processing_timeout_seconds: int = Field(default=120, env="PROCESSING_TIMEOUT")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class MonitoringSettings(BaseSettings):
    """Monitoring and logging configuration."""
    
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    structured_logging: bool = Field(default=True, env="STRUCTURED_LOGGING")
    sentry_dsn: Optional[str] = Field(default=None, env="SENTRY_DSN")
    enable_metrics: bool = Field(default=True, env="ENABLE_METRICS")
    metrics_port: int = Field(default=8001, env="METRICS_PORT")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class DatabaseSettings(BaseSettings):
    """Database configuration."""
    
    bigquery_credentials_path: Optional[str] = Field(
        default=None, env="BIGQUERY_CREDENTIALS_PATH"
    )
    bigquery_location: str = Field(default="US", env="BIGQUERY_LOCATION")
    bigquery_timeout_seconds: int = Field(default=30, env="BQ_TIMEOUT_SECONDS")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


class Settings(BaseSettings):
    """Master settings aggregator."""
    
    environment: str = Field(default="development", env="ENVIRONMENT")
    is_production: bool = Field(default=False, env="IS_PRODUCTION")
    
    # Sub-settings
    cloud: CloudSettings = CloudSettings()
    api: APISettings = APISettings()
    files: FileSettings = FileSettings()
    ai: AISettings = AISettings()
    processing: ProcessingSettings = ProcessingSettings()
    monitoring: MonitoringSettings = MonitoringSettings()
    database: DatabaseSettings = DatabaseSettings()
    
    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """
    Cached settings singleton.
    Returns the same Settings instance across the application.
    """
    return Settings()


# Configuration validation
def validate_settings() -> bool:
    """Validate all settings at startup."""
    try:
        settings = get_settings()
        
        # Validate required fields
        if not settings.cloud.gcp_project_id:
            raise ValueError("GCP_PROJECT_ID not configured")
        
        if not settings.cloud.gcs_bucket:
            raise ValueError("GCS_BUCKET not configured")
        
        if not settings.ai.gemini_api_key:
            raise ValueError("GEMINI_API_KEY not configured")
        
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
    # Test configuration loading
    settings = get_settings()
    print("✓ Settings loaded successfully")
    print(f"  Environment: {settings.environment}")
    print(f"  GCP Project: {settings.cloud.gcp_project_id}")
    print(f"  API Port: {settings.api.port}")
