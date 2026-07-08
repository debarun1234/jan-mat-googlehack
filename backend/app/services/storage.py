"""
Cloud Storage service — media upload for audio and images.

All citizen-submitted media is stored in GCS, never in the database.
The GCS URI is what gets stored in BigQuery (citizen_grievances.raw_input_gcs_uri).
"""

from datetime import datetime

import structlog
from google.cloud import storage
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

log = structlog.get_logger()


class StorageService:
    def __init__(self):
        self._client: storage.Client | None = None
        self._bucket_name = get_settings().gcs_media_bucket

    def _get_client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client()
        return self._client

    def _make_object_path(
        self,
        media_type: str,
        constituency_id: str,
        submission_id: str,
        extension: str,
    ) -> str:
        """
        GCS object path: {type}/{constituency}/{YYYY}/{MM}/{DD}/{submission_id}.{ext}
        Keeps objects partitioned by date for lifecycle rules and cost clarity.
        """
        now = datetime.utcnow()
        return (
            f"{media_type}/{constituency_id}/"
            f"{now.year}/{now.month:02d}/{now.day:02d}/"
            f"{submission_id}.{extension}"
        )

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=6),
        reraise=True,
    )
    async def upload_audio(
        self,
        audio_bytes: bytes,
        submission_id: str,
        constituency_id: str,
        content_type: str = "audio/webm",
    ) -> str:
        """Upload audio bytes. Returns GCS URI (gs://bucket/path)."""
        ext = content_type.split("/")[-1].replace("mpeg", "mp3")
        object_path = self._make_object_path(
            "audio", constituency_id, submission_id, ext
        )
        return await self._upload(audio_bytes, object_path, content_type)

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=6),
        reraise=True,
    )
    async def upload_image(
        self,
        image_bytes: bytes,
        submission_id: str,
        constituency_id: str,
        content_type: str = "image/jpeg",
    ) -> str:
        """Upload image bytes. Returns GCS URI (gs://bucket/path)."""
        ext = content_type.split("/")[-1]
        object_path = self._make_object_path(
            "images", constituency_id, submission_id, ext
        )
        return await self._upload(image_bytes, object_path, content_type)

    async def _upload(
        self,
        data: bytes,
        object_path: str,
        content_type: str,
    ) -> str:
        client = self._get_client()
        bucket = client.bucket(self._bucket_name)
        blob = bucket.blob(object_path)
        blob.upload_from_string(data, content_type=content_type)

        gcs_uri = f"gs://{self._bucket_name}/{object_path}"
        log.info("gcs_upload", uri=gcs_uri, bytes=len(data), content_type=content_type)
        return gcs_uri

    async def download_bytes(self, gcs_uri: str) -> tuple[bytes, str]:
        """
        Download a GCS object and return (bytes, content_type).
        Used by media proxy endpoints so the backend streams files to clients.
        """
        import asyncio

        object_path = gcs_uri.replace(f"gs://{self._bucket_name}/", "")

        def _sync_download():
            client = self._get_client()
            bucket = client.bucket(self._bucket_name)
            blob = bucket.blob(object_path)
            data = blob.download_as_bytes()
            ct = blob.content_type or "application/octet-stream"
            return data, ct

        return await asyncio.get_event_loop().run_in_executor(None, _sync_download)

    async def get_bucket_usage(self) -> dict:
        """
        Return total object count + total bytes across the media bucket.
        Used by the budget tracker to calculate real GCS storage cost.
        """
        import asyncio

        def _sync():
            client = self._get_client()
            total_bytes = 0
            total_objects = 0
            for blob in client.list_blobs(self._bucket_name):
                total_bytes += blob.size or 0
                total_objects += 1
            return {"total_bytes": total_bytes, "total_objects": total_objects}

        try:
            return await asyncio.get_event_loop().run_in_executor(None, _sync)
        except Exception:
            return {"total_bytes": 0, "total_objects": 0}

    async def get_signed_url(self, gcs_uri: str, expiration_seconds: int = 300) -> str:
        """Generate a signed download URL for a GCS object (for debugging/admin only)."""
        object_path = gcs_uri.replace(f"gs://{self._bucket_name}/", "")
        client = self._get_client()
        bucket = client.bucket(self._bucket_name)
        blob = bucket.blob(object_path)
        from datetime import timedelta

        url = blob.generate_signed_url(
            expiration=timedelta(seconds=expiration_seconds),
            method="GET",
        )
        return url


_storage_service: StorageService | None = None


def get_storage_service() -> StorageService:
    global _storage_service
    if _storage_service is None:
        _storage_service = StorageService()
    return _storage_service
