"""
Pydantic request/response schemas for FastAPI.
Provides validation and OpenAPI documentation.
"""

from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum


class InputTypeEnum(str, Enum):
    """Allowed input types."""
    TEXT = "text"
    IMAGE = "image"
    AUDIO = "audio"
    PDF = "pdf"
    FORM = "form"


class UploadRequestBase(BaseModel):
    """Base upload request."""
    
    request_id: Optional[str] = Field(
        None,
        description="Unique request identifier (auto-generated if not provided)"
    )
    input_type: InputTypeEnum = Field(..., description="Type of input being submitted")
    language: Optional[str] = Field(
        default="en",
        description="Language code (ISO 639-1)"
    )
    latitude: Optional[float] = Field(
        None,
        description="Geographic latitude",
        ge=-90,
        le=90
    )
    longitude: Optional[float] = Field(
        None,
        description="Geographic longitude",
        ge=-180,
        le=180
    )
    
    class Config:
        schema_extra = {
            "example": {
                "request_id": "req-2024-001",
                "input_type": "image",
                "language": "en",
                "latitude": 13.1007,
                "longitude": 77.5963
            }
        }


class TextSubmissionRequest(UploadRequestBase):
    """Text input request."""
    
    text: str = Field(..., min_length=10, description="Text content to analyze")
    
    class Config:
        schema_extra = {
            "example": {
                "request_id": "req-text-001",
                "input_type": "text",
                "text": "There is a pothole on Main Street that needs repair",
                "language": "en"
            }
        }


class FileUploadRequest(UploadRequestBase):
    """File upload request base."""
    
    filename: str = Field(..., description="Original filename")
    
    class Config:
        schema_extra = {
            "example": {
                "request_id": "req-img-001",
                "input_type": "image",
                "filename": "pothole.jpg"
            }
        }


class ImageUploadRequest(FileUploadRequest):
    """Image upload request."""
    
    input_type: InputTypeEnum = Field(InputTypeEnum.IMAGE)


class AudioUploadRequest(FileUploadRequest):
    """Audio upload request."""
    
    input_type: InputTypeEnum = Field(InputTypeEnum.AUDIO)


class PDFUploadRequest(FileUploadRequest):
    """PDF upload request."""
    
    input_type: InputTypeEnum = Field(InputTypeEnum.PDF)


class UploadResponse(BaseModel):
    """Response for successful upload."""
    
    request_id: str = Field(..., description="Request identifier")
    status: str = Field(default="accepted", description="Status of the submission")
    message: str = Field(default="Submission accepted for processing")
    gcs_uri: str = Field(..., description="Google Cloud Storage location of uploaded file")
    estimated_processing_time_seconds: int = Field(
        default=120,
        description="Estimated time to complete processing"
    )
    tracking_url: str = Field(..., description="URL to track submission progress")
    
    class Config:
        schema_extra = {
            "example": {
                "request_id": "550e8400-e29b-41d4-a716-446655440000",
                "status": "accepted",
                "message": "Submission accepted for processing",
                "gcs_uri": "gs://janmat-uploads/20240101/550e8400_202401011200_a1b2c3d4.jpg",
                "estimated_processing_time_seconds": 120,
                "tracking_url": "/api/v1/submissions/550e8400-e29b-41d4-a716-446655440000"
            }
        }


class ErrorResponse(BaseModel):
    """Error response."""
    
    error_code: str = Field(..., description="Machine-readable error code")
    message: str = Field(..., description="Human-readable error message")
    request_id: Optional[str] = Field(None, description="Request ID if available")
    details: Optional[Dict[str, Any]] = Field(None, description="Additional error details")
    
    class Config:
        schema_extra = {
            "example": {
                "error_code": "FILE_TOO_LARGE",
                "message": "File size exceeds maximum of 100MB",
                "request_id": "550e8400-e29b-41d4-a716-446655440000",
                "details": {"max_size_mb": 100, "provided_size_mb": 150}
            }
        }


class HealthCheckResponse(BaseModel):
    """Health check response."""
    
    status: str = Field(default="healthy")
    version: str = Field(..., description="API version")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    components: Dict[str, str] = Field(
        default_factory=lambda: {
            "api": "healthy",
            "gcs": "healthy",
            "bigquery": "healthy",
            "pubsub": "healthy"
        },
        description="Status of each component"
    )


class ReadinessResponse(BaseModel):
    """Readiness check response."""
    
    ready: bool = Field(...)
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    checks: Dict[str, bool] = Field(default_factory=dict)


class MetricsResponse(BaseModel):
    """Metrics response."""
    
    uploaded_files_total: int
    uploaded_bytes_total: int
    validation_failures: int
    extraction_failures: int
    ai_api_calls_total: int
    ai_api_failures: int
    bigquery_inserts_total: int
    bigquery_insert_failures: int
    processing_time_avg_ms: Optional[float]
    processing_time_p99_ms: Optional[float]
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class SubmissionStatusResponse(BaseModel):
    """Submission status response."""
    
    request_id: str
    status: str = Field(..., description="Status: processing, completed, failed")
    progress_percent: int
    stage: Optional[str] = Field(None, description="Current processing stage")
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        schema_extra = {
            "example": {
                "request_id": "550e8400-e29b-41d4-a716-446655440000",
                "status": "processing",
                "progress_percent": 45,
                "stage": "ai_inference",
                "created_at": "2024-01-01T12:00:00Z",
                "updated_at": "2024-01-01T12:02:30Z"
            }
        }


class AIInferenceResult(BaseModel):
    """AI inference result."""
    
    category: str = Field(..., description="Grievance category")
    priority: str = Field(..., description="Priority level")
    sentiment: str = Field(..., description="Sentiment analysis")
    summary_en: str = Field(..., description="English summary")
    confidence_score: float = Field(..., ge=0.0, le=1.0)


class PipelineAuditLog(BaseModel):
    """Pipeline audit log entry."""
    
    audit_id: str
    request_id: str
    upload_status: str
    extract_status: str
    transform_status: str
    ai_status: str
    load_status: str
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    processing_time_ms: Optional[int] = None
    file_size_bytes: Optional[int] = None
    input_type: Optional[str] = None
    created_at: datetime
    updated_at: datetime


# Request body for direct text analysis
class AnalyzeTextRequest(BaseModel):
    """Direct text analysis request."""
    
    text: str = Field(..., min_length=10, description="Text to analyze")
    request_id: Optional[str] = None
    language: str = Field(default="en")
    
    class Config:
        schema_extra = {
            "example": {
                "text": "The hospital has no emergency department, patients must travel 30km for emergency care",
                "language": "en"
            }
        }
