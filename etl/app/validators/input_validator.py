"""
Input validation module (CP-1 checkpoint).
Validates file type, size, format, and request structure.
"""

import logging
from typing import Optional, Dict, Any
from datetime import datetime

from app.config.settings import get_settings
from app.utils.errors import ValidationError, ErrorCode


logger = logging.getLogger(__name__)


class InputValidator:
    """Validates incoming requests at CP-1."""

    def __init__(self):
        self.settings = get_settings()
        self.max_file_size = self.settings.files.max_file_size_mb * 1024 * 1024

    def validate_request_id(self, request_id: Optional[str]) -> str:
        """Validate or generate request ID."""

        if not request_id:
            # Generate UUID
            from uuid import uuid4

            request_id = str(uuid4())

        # Validate format (alphanumeric and hyphens)
        if not all(c.isalnum() or c == "-" for c in request_id):
            raise ValidationError(
                message="Invalid request_id format",
                error_code=ErrorCode.MALFORMED_REQUEST,
                details={"request_id": request_id},
            )

        if len(request_id) > 100:
            raise ValidationError(
                message="request_id too long", error_code=ErrorCode.MALFORMED_REQUEST
            )

        return request_id

    def validate_input_type(self, input_type: str) -> str:
        """Validate input type."""

        valid_types = ["image", "audio", "pdf", "text", "form"]

        if input_type not in valid_types:
            raise ValidationError(
                message=f"Invalid input_type. Must be one of: {', '.join(valid_types)}",
                error_code=ErrorCode.INVALID_FILE_TYPE,
                details={"input_type": input_type},
            )

        return input_type

    def validate_file_type(self, input_type: str, content_type: str) -> bool:
        """Validate MIME type against input type."""

        allowed_types = {
            "image": self.settings.files.allowed_image_types,
            "audio": self.settings.files.allowed_audio_types,
            "pdf": self.settings.files.allowed_pdf_types,
        }

        if input_type not in allowed_types:
            # Text and form don't require file type validation
            return True

        allowed = allowed_types[input_type]

        if content_type not in allowed:
            raise ValidationError(
                message=f"Invalid content type for {input_type}. Must be one of: {', '.join(allowed)}",
                error_code=ErrorCode.INVALID_FILE_TYPE,
                details={
                    "input_type": input_type,
                    "content_type": content_type,
                    "allowed": allowed,
                },
            )

        return True

    def validate_file_size(self, file_size: int, input_type: str) -> bool:
        """Validate file size."""

        if file_size <= 0:
            raise ValidationError(
                message="File size must be greater than 0",
                error_code=ErrorCode.FILE_TOO_SMALL,
                details={"file_size": file_size},
            )

        if file_size > self.max_file_size:
            raise ValidationError(
                message=f"File too large. Maximum size: {self.settings.files.max_file_size_mb}MB",
                error_code=ErrorCode.FILE_TOO_LARGE,
                details={"file_size": file_size, "max_size": self.max_file_size},
            )

        return True

    def validate_file_not_empty(self, file_content: bytes) -> bool:
        """Validate file is not empty."""

        if not file_content or len(file_content) == 0:
            raise ValidationError(
                message="File content is empty",
                error_code=ErrorCode.FILE_TOO_SMALL,
                details={"content_length": len(file_content)},
            )

        return True

    def validate_file_signature(self, file_content: bytes, input_type: str) -> bool:
        """Validate file signature (magic bytes)."""

        import magic

        try:
            mime = magic.from_buffer(file_content, mime=True)

            # Validate mime type matches input type
            if input_type == "image":
                if not mime.startswith("image/"):
                    raise ValidationError(
                        message=f"File signature doesn't match image type: {mime}",
                        error_code=ErrorCode.CORRUPTED_FILE,
                        details={"detected_mime": mime},
                    )

            elif input_type == "audio":
                if not mime.startswith("audio/"):
                    raise ValidationError(
                        message=f"File signature doesn't match audio type: {mime}",
                        error_code=ErrorCode.CORRUPTED_FILE,
                        details={"detected_mime": mime},
                    )

            elif input_type == "pdf":
                if mime != "application/pdf":
                    raise ValidationError(
                        message=f"File signature doesn't match PDF type: {mime}",
                        error_code=ErrorCode.CORRUPTED_FILE,
                        details={"detected_mime": mime},
                    )

            return True

        except ValidationError:
            raise

        except Exception as e:
            logger.warning(f"Magic bytes validation failed: {str(e)}")
            # Don't fail on magic bytes error, just warn
            return True

    def validate_text_content(self, text: str) -> bool:
        """Validate text content."""

        if not text or len(text.strip()) == 0:
            raise ValidationError(
                message="Text content is empty",
                error_code=ErrorCode.MISSING_REQUIRED_FIELD,
                details={"text_length": len(text)},
            )

        # Check for minimum length
        min_length = self.settings.processing.min_text_length
        if len(text.strip()) < min_length:
            raise ValidationError(
                message=f"Text too short. Minimum: {min_length} characters",
                error_code=ErrorCode.FILE_TOO_SMALL,
                details={"text_length": len(text), "min_length": min_length},
            )

        # Check for maximum length
        max_length = self.settings.processing.max_text_length
        if len(text) > max_length:
            raise ValidationError(
                message=f"Text too long. Maximum: {max_length} characters",
                error_code=ErrorCode.FILE_TOO_LARGE,
                details={"text_length": len(text), "max_length": max_length},
            )

        return True

    def validate_language(self, language_code: str) -> bool:
        """Validate language code."""

        valid_languages = {
            "en",
            "hi",
            "ka",
            "ta",
            "te",
            "bn",
            "mr",
            "gu",
            "ml",
            "kn",
            "pa",
            "ur",
        }

        if language_code not in valid_languages:
            logger.warning(f"Unsupported language: {language_code}")
            # Don't fail, just warn

        return True

    def validate_location(
        self, latitude: Optional[float], longitude: Optional[float]
    ) -> bool:
        """Validate geographic coordinates."""

        if latitude is None or longitude is None:
            return True  # Location is optional

        # Validate ranges
        if not (-90 <= latitude <= 90):
            raise ValidationError(
                message="Latitude out of range (-90 to 90)",
                error_code=ErrorCode.MALFORMED_REQUEST,
                details={"latitude": latitude},
            )

        if not (-180 <= longitude <= 180):
            raise ValidationError(
                message="Longitude out of range (-180 to 180)",
                error_code=ErrorCode.MALFORMED_REQUEST,
                details={"longitude": longitude},
            )

        # Validate for Karnataka region (optional additional check)
        # Karnataka bounds: ~12.5-18.5°N, 74-78.5°E
        if not (12 <= latitude <= 19 and 74 <= longitude <= 79):
            logger.warning(
                f"Location outside expected Karnataka region: {latitude}, {longitude}"
            )

        return True

    def validate_timestamp(self, timestamp: Optional[datetime]) -> bool:
        """Validate timestamp is not in future."""

        if timestamp is None:
            return True

        now = datetime.utcnow()
        if timestamp > now:
            raise ValidationError(
                message="Timestamp cannot be in the future",
                error_code=ErrorCode.MALFORMED_REQUEST,
                details={
                    "timestamp": timestamp.isoformat(),
                    "current_time": now.isoformat(),
                },
            )

        # Also check not too old (more than 30 days)
        from datetime import timedelta

        if (now - timestamp) > timedelta(days=30):
            logger.warning(f"Timestamp is older than 30 days: {timestamp}")

        return True

    def validate_full_upload_request(
        self,
        request_id: str,
        input_type: str,
        file_size: int,
        content_type: str,
        file_content: bytes,
        request_body: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Full validation of an upload request (CP-1).

        Args:
            request_id: Request identifier
            input_type: Type of input
            file_size: Size of file
            content_type: MIME type
            file_content: Raw file bytes
            request_body: Additional request parameters

        Returns:
            Validated request data

        Raises:
            ValidationError: If any validation fails
        """

        # Validate components
        validated_request_id = self.validate_request_id(request_id)
        validated_input_type = self.validate_input_type(input_type)
        self.validate_file_size(file_size, input_type)
        self.validate_file_type(input_type, content_type)
        self.validate_file_not_empty(file_content)

        # Signature check
        if input_type in ["image", "audio", "pdf"]:
            self.validate_file_signature(file_content, input_type)

        # Validate request body if present
        if request_body:
            if "language" in request_body:
                self.validate_language(request_body["language"])

            if "latitude" in request_body and "longitude" in request_body:
                self.validate_location(
                    request_body.get("latitude"), request_body.get("longitude")
                )

            if "timestamp" in request_body:
                try:
                    ts = datetime.fromisoformat(request_body["timestamp"])
                    self.validate_timestamp(ts)
                except (ValueError, TypeError):
                    raise ValidationError(
                        message="Invalid timestamp format",
                        error_code=ErrorCode.MALFORMED_REQUEST,
                    )

        return {
            "request_id": validated_request_id,
            "input_type": validated_input_type,
            "file_size": file_size,
            "content_type": content_type,
            "validation_passed_at": datetime.utcnow(),
            "validation_stage": "CP-1",
        }


def get_input_validator() -> InputValidator:
    """Get validator instance."""
    if not hasattr(get_input_validator, "_instance"):
        get_input_validator._instance = InputValidator()
    return get_input_validator._instance
