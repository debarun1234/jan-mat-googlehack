"""
Structured logging and monitoring setup.
Provides JSON-formatted logs and metrics collection.
"""

import logging
import json
import time
from typing import Optional, Dict, Any
from datetime import datetime
from pythonjsonlogger import jsonlogger
from functools import wraps
import sys


class StructuredLogger:
    """Wrapper for structured JSON logging."""
    
    def __init__(self, name: str):
        self.logger = logging.getLogger(name)
        self._setup_handlers()
    
    def _setup_handlers(self):
        """Configure JSON logging handlers."""
        
        # Remove existing handlers
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)
        
        # Console handler with JSON formatter
        console_handler = logging.StreamHandler(sys.stdout)
        json_formatter = jsonlogger.JsonFormatter(
            fmt='%(timestamp)s %(level)s %(name)s %(message)s %(request_id)s %(stage)s %(error_code)s'
        )
        console_handler.setFormatter(json_formatter)
        self.logger.addHandler(console_handler)
        
        self.logger.setLevel(logging.INFO)
    
    def _add_defaults(self, kwargs: Dict[str, Any]) -> Dict[str, Any]:
        """Add default fields to log."""
        defaults = {
            'timestamp': datetime.utcnow().isoformat(),
            'request_id': kwargs.pop('request_id', None),
            'stage': kwargs.pop('stage', None),
            'error_code': kwargs.pop('error_code', None),
        }
        kwargs.update(defaults)
        return kwargs
    
    def info(self, message: str, **kwargs):
        """Log info level."""
        self.logger.info(message, extra=self._add_defaults(kwargs))
    
    def warning(self, message: str, **kwargs):
        """Log warning level."""
        self.logger.warning(message, extra=self._add_defaults(kwargs))
    
    def error(self, message: str, **kwargs):
        """Log error level."""
        self.logger.error(message, extra=self._add_defaults(kwargs))
    
    def debug(self, message: str, **kwargs):
        """Log debug level."""
        self.logger.debug(message, extra=self._add_defaults(kwargs))
    
    def critical(self, message: str, **kwargs):
        """Log critical level."""
        self.logger.critical(message, extra=self._add_defaults(kwargs))


class MetricsCollector:
    """Simple metrics collection without external dependencies."""
    
    def __init__(self):
        self.logger = StructuredLogger(__name__)
        self.metrics: Dict[str, Any] = {
            "uploaded_files_total": 0,
            "uploaded_bytes_total": 0,
            "validation_failures": 0,
            "extraction_failures": 0,
            "ai_api_calls_total": 0,
            "ai_api_failures": 0,
            "bigquery_inserts_total": 0,
            "bigquery_insert_failures": 0,
            "pubsub_publishes_total": 0,
            "pubsub_failures": 0,
            "dlq_messages_total": 0,
            "processing_times": [],
        }
    
    def increment_counter(self, counter_name: str, value: int = 1):
        """Increment a counter metric."""
        if counter_name in self.metrics:
            self.metrics[counter_name] += value
            self.logger.debug(
                f"Metric incremented",
                metric=counter_name,
                value=self.metrics[counter_name]
            )
    
    def record_processing_time(self, duration_ms: float):
        """Record processing time in milliseconds."""
        self.metrics["processing_times"].append(duration_ms)
    
    def record_bytes(self, bytes_count: int):
        """Record uploaded bytes."""
        self.increment_counter("uploaded_bytes_total", bytes_count)
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get all current metrics."""
        metrics_copy = self.metrics.copy()
        
        # Calculate statistics
        if metrics_copy["processing_times"]:
            times = metrics_copy["processing_times"]
            metrics_copy["processing_time_avg_ms"] = sum(times) / len(times)
            metrics_copy["processing_time_max_ms"] = max(times)
            metrics_copy["processing_time_min_ms"] = min(times)
        
        return metrics_copy
    
    def reset_metrics(self):
        """Reset all metrics (for testing)."""
        self.metrics = {
            "uploaded_files_total": 0,
            "uploaded_bytes_total": 0,
            "validation_failures": 0,
            "extraction_failures": 0,
            "ai_api_calls_total": 0,
            "ai_api_failures": 0,
            "bigquery_inserts_total": 0,
            "bigquery_insert_failures": 0,
            "pubsub_publishes_total": 0,
            "pubsub_failures": 0,
            "dlq_messages_total": 0,
            "processing_times": [],
        }


# Global metrics instance
_metrics_collector = MetricsCollector()


def get_metrics_collector() -> MetricsCollector:
    """Get the global metrics collector."""
    return _metrics_collector


def get_logger(name: str) -> StructuredLogger:
    """Get a structured logger instance."""
    return StructuredLogger(name)


def log_duration(stage: str):
    """Decorator to log operation duration."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            logger = get_logger(func.__module__)
            request_id = kwargs.get('request_id') or getattr(args[0], 'request_id', None)
            
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                duration_ms = (time.time() - start_time) * 1000
                
                logger.info(
                    f"{stage} completed",
                    stage=stage,
                    request_id=request_id,
                    duration_ms=round(duration_ms, 2)
                )
                _metrics_collector.record_processing_time(duration_ms)
                
                return result
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                logger.error(
                    f"{stage} failed",
                    stage=stage,
                    request_id=request_id,
                    duration_ms=round(duration_ms, 2),
                    error=str(e)
                )
                raise
        
        return wrapper
    return decorator


def log_operation(operation_name: str):
    """Decorator for logging general operations."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            logger = get_logger(func.__module__)
            
            try:
                result = func(*args, **kwargs)
                logger.info(f"{operation_name} succeeded")
                return result
            except Exception as e:
                logger.error(
                    f"{operation_name} failed",
                    error=str(e),
                    error_type=type(e).__name__
                )
                raise
        
        return wrapper
    return decorator


class AuditLog:
    """Structured audit logging for pipeline events."""
    
    def __init__(self):
        self.logger = get_logger("audit")
    
    def log_submission_received(self, request_id: str, input_type: str, file_size: int):
        """Log when a submission is received."""
        self.logger.info(
            "Submission received",
            request_id=request_id,
            event="submission_received",
            input_type=input_type,
            file_size=file_size
        )
    
    def log_validation_passed(self, request_id: str):
        """Log successful validation."""
        self.logger.info(
            "Validation passed",
            request_id=request_id,
            event="validation_passed"
        )
    
    def log_validation_failed(self, request_id: str, error_code: str, reason: str):
        """Log validation failure."""
        self.logger.warning(
            "Validation failed",
            request_id=request_id,
            event="validation_failed",
            error_code=error_code,
            reason=reason
        )
    
    def log_storage_completed(self, request_id: str, gcs_uri: str):
        """Log successful storage."""
        self.logger.info(
            "Storage completed",
            request_id=request_id,
            event="storage_completed",
            gcs_uri=gcs_uri
        )
    
    def log_extraction_completed(self, request_id: str, text_length: int):
        """Log successful extraction."""
        self.logger.info(
            "Extraction completed",
            request_id=request_id,
            event="extraction_completed",
            text_length=text_length
        )
    
    def log_ai_inference_completed(self, request_id: str, category: str, confidence: float):
        """Log successful AI inference."""
        self.logger.info(
            "AI inference completed",
            request_id=request_id,
            event="ai_inference_completed",
            category=category,
            confidence=confidence
        )
    
    def log_bigquery_insert_completed(self, request_id: str, row_count: int):
        """Log successful BigQuery insert."""
        self.logger.info(
            "BigQuery insert completed",
            request_id=request_id,
            event="bigquery_insert_completed",
            row_count=row_count
        )
    
    def log_error(self, request_id: str, stage: str, error_code: str, message: str):
        """Log pipeline error."""
        self.logger.error(
            "Pipeline error",
            request_id=request_id,
            event="pipeline_error",
            stage=stage,
            error_code=error_code,
            message=message
        )


def get_audit_logger() -> AuditLog:
    """Get the audit logger instance."""
    return AuditLog()
