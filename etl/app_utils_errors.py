"""
Custom exception hierarchy and error handling utilities.
Provides typed errors for all pipeline stages.
"""

from typing import Optional, Any, Dict
from enum import Enum
import logging


logger = logging.getLogger(__name__)


class ErrorCode(str, Enum):
    """Standard error codes for all failures."""
    
    # Input validation errors
    INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    FILE_TOO_SMALL = "FILE_TOO_SMALL"
    CORRUPTED_FILE = "CORRUPTED_FILE"
    MISSING_REQUIRED_FIELD = "MISSING_REQUIRED_FIELD"
    MALFORMED_REQUEST = "MALFORMED_REQUEST"
    DUPLICATE_SUBMISSION = "DUPLICATE_SUBMISSION"
    
    # Storage errors
    GCS_UPLOAD_FAILED = "GCS_UPLOAD_FAILED"
    GCS_DOWNLOAD_FAILED = "GCS_DOWNLOAD_FAILED"
    GCS_PERMISSION_DENIED = "GCS_PERMISSION_DENIED"
    GCS_QUOTA_EXCEEDED = "GCS_QUOTA_EXCEEDED"
    
    # Extraction errors
    EXTRACTION_FAILED = "EXTRACTION_FAILED"
    OCR_FAILED = "OCR_FAILED"
    STT_FAILED = "STT_FAILED"
    PDF_PARSE_FAILED = "PDF_PARSE_FAILED"
    LANGUAGE_DETECTION_FAILED = "LANGUAGE_DETECTION_FAILED"
    
    # AI/Gemini errors
    AI_API_ERROR = "AI_API_ERROR"
    AI_INVALID_RESPONSE = "AI_INVALID_RESPONSE"
    AI_TIMEOUT = "AI_TIMEOUT"
    AI_RATE_LIMITED = "AI_RATE_LIMITED"
    AI_QUOTA_EXCEEDED = "AI_QUOTA_EXCEEDED"
    AI_AUTHENTICATION_FAILED = "AI_AUTHENTICATION_FAILED"
    AI_VALIDATION_FAILED = "AI_VALIDATION_FAILED"
    
    # Database errors
    BIGQUERY_INSERT_FAILED = "BIGQUERY_INSERT_FAILED"
    BIGQUERY_SCHEMA_MISMATCH = "BIGQUERY_SCHEMA_MISMATCH"
    BIGQUERY_DUPLICATE_KEY = "BIGQUERY_DUPLICATE_KEY"
    BIGQUERY_PERMISSION_DENIED = "BIGQUERY_PERMISSION_DENIED"
    BIGQUERY_QUOTA_EXCEEDED = "BIGQUERY_QUOTA_EXCEEDED"
    BIGQUERY_TIMEOUT = "BIGQUERY_TIMEOUT"
    
    # Queue errors
    PUBSUB_PUBLISH_FAILED = "PUBSUB_PUBLISH_FAILED"
    PUBSUB_CONSUME_FAILED = "PUBSUB_CONSUME_FAILED"
    
    # Transformation errors
    TRANSFORMATION_FAILED = "TRANSFORMATION_FAILED"
    DATA_VALIDATION_FAILED = "DATA_VALIDATION_FAILED"
    
    # System errors
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    TIMEOUT = "TIMEOUT"
    CONFIGURATION_ERROR = "CONFIGURATION_ERROR"
    
    # Unknown errors
    UNKNOWN_ERROR = "UNKNOWN_ERROR"


class PipelineException(Exception):
    """
    Base exception for all pipeline-related errors.
    Provides structured error information for logging and audit trails.
    """
    
    def __init__(
        self,
        error_code: ErrorCode,
        message: str,
        request_id: Optional[str] = None,
        stage: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        self.error_code = error_code
        self.message = message
        self.request_id = request_id
        self.stage = stage
        self.details = details or {}
        self.original_exception = original_exception
        self.retry_eligible = retry_eligible
        
        super().__init__(self.message)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "error_code": self.error_code.value,
            "message": self.message,
            "request_id": self.request_id,
            "stage": self.stage,
            "details": self.details,
            "retry_eligible": self.retry_eligible
        }
    
    def __str__(self) -> str:
        base = f"[{self.error_code.value}] {self.message}"
        if self.request_id:
            base = f"[{self.request_id}] {base}"
        if self.stage:
            base = f"{base} (stage: {self.stage})"
        return base


class ValidationError(PipelineException):
    """Raised when input validation fails."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="validation",
            details=details,
            retry_eligible=False
        )


class StorageError(PipelineException):
    """Raised when Cloud Storage operations fail."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.GCS_UPLOAD_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="storage",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class ExtractionError(PipelineException):
    """Raised when extraction operations fail."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.EXTRACTION_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="extraction",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class AIError(PipelineException):
    """Raised when AI/Gemini operations fail."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.AI_API_ERROR,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="ai_inference",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class AIValidationError(PipelineException):
    """Raised when AI output validation fails."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.AI_VALIDATION_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="ai_validation",
            details=details,
            original_exception=original_exception,
            retry_eligible=False  # Don't retry AI validation failures
        )


class TransformationError(PipelineException):
    """Raised when data transformation fails."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.TRANSFORMATION_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="transformation",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class DatabaseError(PipelineException):
    """Raised when BigQuery operations fail."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.BIGQUERY_INSERT_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="database",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class QueueError(PipelineException):
    """Raised when Pub/Sub operations fail."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.PUBSUB_PUBLISH_FAILED,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        original_exception: Optional[Exception] = None,
        retry_eligible: bool = True
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            request_id=request_id,
            stage="queue",
            details=details,
            original_exception=original_exception,
            retry_eligible=retry_eligible
        )


class ConfigurationError(PipelineException):
    """Raised when configuration is invalid or missing."""
    
    def __init__(
        self,
        message: str,
        error_code: ErrorCode = ErrorCode.CONFIGURATION_ERROR,
        details: Optional[Dict[str, Any]] = None
    ):
        super().__init__(
            error_code=error_code,
            message=message,
            stage="configuration",
            details=details,
            retry_eligible=False
        )


def get_retry_eligibility(error_code: ErrorCode) -> bool:
    """Determine if an error is eligible for retry based on error code."""
    
    # Errors that should NOT be retried
    non_retryable = {
        ErrorCode.INVALID_FILE_TYPE,
        ErrorCode.FILE_TOO_LARGE,
        ErrorCode.FILE_TOO_SMALL,
        ErrorCode.MISSING_REQUIRED_FIELD,
        ErrorCode.MALFORMED_REQUEST,
        ErrorCode.DUPLICATE_SUBMISSION,
        ErrorCode.BIGQUERY_SCHEMA_MISMATCH,
        ErrorCode.BIGQUERY_DUPLICATE_KEY,
        ErrorCode.AI_VALIDATION_FAILED,
        ErrorCode.CONFIGURATION_ERROR,
    }
    
    return error_code not in non_retryable


def log_exception(error: PipelineException) -> None:
    """Structured logging for exceptions."""
    
    log_data = {
        "error_code": error.error_code.value,
        "message": error.message,
        "request_id": error.request_id,
        "stage": error.stage,
        "details": error.details,
        "retry_eligible": error.retry_eligible
    }
    
    if error.original_exception:
        log_data["original_error"] = str(error.original_exception)
    
    logger.error("Pipeline error", extra=log_data)
