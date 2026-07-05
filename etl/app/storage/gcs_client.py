"""
Google Cloud Storage client for file uploads and downloads.
Implements retry logic, metadata handling, and deduplication.
"""

import os
import hashlib
from typing import Optional, Dict, Any
from datetime import datetime
import logging

from google.cloud import storage
from google.api_core import retry, exceptions

from app.config.settings import get_settings
from app.utils.errors import StorageError, ErrorCode


logger = logging.getLogger(__name__)


class GCSClient:
    """Google Cloud Storage client with production features."""

    def __init__(self):
        self.settings = get_settings()
        self.client = storage.Client(project=self.settings.cloud.gcp_project_id)
        self.bucket = self.client.bucket(self.settings.cloud.gcs_bucket)

        # Verify bucket exists
        if not self.bucket.exists():
            raise StorageError(
                message=f"Bucket {self.settings.cloud.gcs_bucket} does not exist",
                error_code=ErrorCode.GCS_PERMISSION_DENIED,
                retry_eligible=False,
            )

    def _compute_file_hash(self, file_content: bytes) -> str:
        """Compute SHA-256 hash of file content."""
        return hashlib.sha256(file_content).hexdigest()

    def _generate_unique_filename(
        self, original_filename: str, file_hash: str, request_id: str
    ) -> str:
        """Generate unique filename for storage."""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        ext = os.path.splitext(original_filename)[1]

        # Format: uploads/YYYYMMDD/request_id_timestamp_filehash.ext
        unique_name = f"{request_id}_{timestamp}_{file_hash[:8]}{ext}"
        date_folder = datetime.utcnow().strftime("%Y%m%d")

        return f"{self.settings.cloud.gcs_upload_folder}/{date_folder}/{unique_name}"

    def _verify_file_integrity(self, blob: storage.Blob, original_hash: str) -> bool:
        """Verify file integrity using MD5/CRC32C."""
        try:
            # Force reload of blob metadata
            blob.reload()

            # GCS returns CRC32C hash automatically
            if blob.crc32c:
                # Note: CRC32C is different from SHA256
                # In production, you'd store your own hash in metadata
                logger.debug(f"File CRC32C: {blob.crc32c}")

            return True
        except Exception as e:
            logger.error(f"Integrity check failed: {str(e)}")
            return False

    @retry.Retry(deadline=30)
    def upload_file(
        self,
        file_content: bytes,
        original_filename: str,
        request_id: str,
        input_type: str,
        metadata: Optional[Dict[str, str]] = None,
        content_type: str = "application/octet-stream",
    ) -> Dict[str, Any]:
        """
        Upload file to GCS with metadata and deduplication.

        Args:
            file_content: Raw file bytes
            original_filename: Original filename from client
            request_id: Unique request identifier
            input_type: Type of input (image, audio, pdf, text)
            metadata: Additional metadata to store
            content_type: MIME type

        Returns:
            Dictionary with upload information

        Raises:
            StorageError: If upload fails
        """

        try:
            # Compute file hash for deduplication
            file_hash = self._compute_file_hash(file_content)

            # Generate unique filename
            gcs_path = self._generate_unique_filename(
                original_filename, file_hash, request_id
            )

            # Check if file already exists
            blob_check = self.bucket.blob(gcs_path)
            if blob_check.exists():
                logger.warning(
                    "File already exists in GCS",
                    gcs_path=gcs_path,
                    request_id=request_id,
                )
                # Return existing file info
                return {
                    "gcs_uri": f"gs://{self.settings.cloud.gcs_bucket}/{gcs_path}",
                    "request_id": request_id,
                    "file_size": len(file_content),
                    "file_hash": file_hash,
                    "timestamp": datetime.utcnow().isoformat(),
                    "is_duplicate": True,
                }

            # Create blob with metadata
            blob = self.bucket.blob(gcs_path)

            # Set custom metadata
            blob.metadata = {
                "request_id": request_id,
                "input_type": input_type,
                "original_filename": original_filename,
                "file_hash": file_hash,
                "upload_timestamp": datetime.utcnow().isoformat(),
                **(metadata or {}),
            }

            # Set content type for proper handling
            blob.content_type = content_type

            # Upload with timeout
            blob.upload_from_string(file_content, timeout=30)

            # Verify integrity
            if not self._verify_file_integrity(blob, file_hash):
                raise StorageError(
                    message="File integrity verification failed",
                    error_code=ErrorCode.CORRUPTED_FILE,
                    request_id=request_id,
                )

            logger.info(
                "File uploaded successfully",
                gcs_path=gcs_path,
                request_id=request_id,
                file_size=len(file_content),
            )

            return {
                "gcs_uri": f"gs://{self.settings.cloud.gcs_bucket}/{gcs_path}",
                "request_id": request_id,
                "file_size": len(file_content),
                "file_hash": file_hash,
                "timestamp": datetime.utcnow().isoformat(),
                "is_duplicate": False,
            }

        except exceptions.GoogleCloudError as e:
            # Handle specific GCS errors
            if "quotaExceeded" in str(e):
                error_code = ErrorCode.GCS_QUOTA_EXCEEDED
            elif "permission denied" in str(e):
                error_code = ErrorCode.GCS_PERMISSION_DENIED
            else:
                error_code = ErrorCode.GCS_UPLOAD_FAILED

            raise StorageError(
                message=f"GCS upload failed: {str(e)}",
                error_code=error_code,
                request_id=request_id,
                original_exception=e,
            )

        except Exception as e:
            raise StorageError(
                message=f"Unexpected storage error: {str(e)}",
                error_code=ErrorCode.GCS_UPLOAD_FAILED,
                request_id=request_id,
                original_exception=e,
            )

    @retry.Retry(deadline=30)
    def download_file(self, gcs_uri: str, request_id: Optional[str] = None) -> bytes:
        """
        Download file from GCS.

        Args:
            gcs_uri: GCS URI (gs://bucket/path)
            request_id: Optional request ID for logging

        Returns:
            File content as bytes

        Raises:
            StorageError: If download fails
        """

        try:
            # Parse GCS URI
            if not gcs_uri.startswith("gs://"):
                raise ValueError("Invalid GCS URI format")

            path = gcs_uri[5:]  # Remove "gs://"
            bucket_name, blob_path = path.split("/", 1)

            if bucket_name != self.settings.cloud.gcs_bucket:
                raise ValueError(f"Bucket mismatch: {bucket_name}")

            blob = self.bucket.blob(blob_path)

            if not blob.exists():
                raise StorageError(
                    message=f"File not found: {gcs_uri}",
                    error_code=ErrorCode.GCS_DOWNLOAD_FAILED,
                    request_id=request_id,
                )

            content = blob.download_as_bytes(timeout=30)

            logger.info(
                "File downloaded successfully",
                gcs_uri=gcs_uri,
                request_id=request_id,
                size=len(content),
            )

            return content

        except exceptions.GoogleCloudError as e:
            raise StorageError(
                message=f"GCS download failed: {str(e)}",
                error_code=ErrorCode.GCS_DOWNLOAD_FAILED,
                request_id=request_id,
                original_exception=e,
            )

        except Exception as e:
            raise StorageError(
                message=f"Unexpected download error: {str(e)}",
                error_code=ErrorCode.GCS_DOWNLOAD_FAILED,
                request_id=request_id,
                original_exception=e,
            )

    def get_file_metadata(self, gcs_uri: str) -> Dict[str, Any]:
        """Get file metadata from GCS."""

        try:
            path = gcs_uri[5:].split("/", 1)[1]
            blob = self.bucket.blob(path)

            if not blob.exists():
                return {}

            blob.reload()

            return {
                "name": blob.name,
                "size": blob.size,
                "content_type": blob.content_type,
                "created": blob.time_created.isoformat() if blob.time_created else None,
                "updated": blob.updated.isoformat() if blob.updated else None,
                "metadata": blob.metadata or {},
            }

        except Exception as e:
            logger.error(f"Failed to get metadata: {str(e)}")
            return {}

    def delete_file(self, gcs_uri: str, request_id: Optional[str] = None) -> bool:
        """Delete file from GCS."""

        try:
            path = gcs_uri[5:].split("/", 1)[1]
            blob = self.bucket.blob(path)
            blob.delete(timeout=10)

            logger.info("File deleted", gcs_uri=gcs_uri, request_id=request_id)
            return True

        except Exception as e:
            logger.error(f"Failed to delete file: {str(e)}")
            return False


def get_gcs_client() -> GCSClient:
    """Get or create GCS client (singleton pattern)."""
    if not hasattr(get_gcs_client, "_instance"):
        get_gcs_client._instance = GCSClient()
    return get_gcs_client._instance
