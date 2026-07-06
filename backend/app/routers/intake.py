"""
Phase 1 — Citizen Intake Router

Endpoints:
  POST /intake/text    — text submission (any Indic language or English)
  POST /intake/audio   — voice note upload
  POST /intake/image   — photo upload
  GET  /intake/status/{submission_id}  — check processing status
"""

import uuid
from datetime import datetime, timezone
from typing import Annotated

import structlog
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Header,
    UploadFile,
    status,
)
from google.cloud import firestore
from pydantic import BaseModel, Field

from app.config import Settings, get_settings
from app.services.bigquery import BigQueryService, get_bigquery_service
from app.services.gemini import GeminiService, get_gemini_service
from app.services.pubsub import PubSubService, get_pubsub_service
from app.services.speech import SpeechService, get_speech_service
from app.services.storage import StorageService, get_storage_service
from app.services.translation import TranslationService, get_translation_service

log = structlog.get_logger()
router = APIRouter(prefix="/intake", tags=["intake"])

# ── Firestore submission tracking ─────────────────────────────────────
_db: firestore.AsyncClient | None = None


def _get_db(settings: Settings) -> firestore.AsyncClient:
    global _db
    if _db is None:
        _db = firestore.AsyncClient(project=settings.gcp_project_id)
    return _db


def _firebase_uid_from_token(authorization: str | None) -> str | None:
    """Extract firebase_uid from our JWT without hard-failing — intake is optional-auth."""
    if not authorization or not authorization.startswith("Bearer "):
        return None
    try:
        from jose import jwt as jose_jwt
        from app.config import get_settings as _gs
        s = _gs()
        payload = jose_jwt.decode(
            authorization.split(" ", 1)[1],
            s.jwt_secret,
            algorithms=[s.jwt_algorithm],
        )
        return payload.get("firebase_uid")
    except Exception:
        return None


async def _track_submission(
    settings: Settings,
    firebase_uid: str,
    submission_id: str,
    input_type: str,
    category: str,
    urgency: int,
    summary: str,
    lat: float | None,
    lng: float | None,
) -> None:
    """Write submission metadata to Firestore and increment submission_count."""
    try:
        db = _get_db(settings)
        user_ref = db.collection("janmat_users").document(firebase_uid)
        sub_ref  = user_ref.collection("submissions").document(submission_id)

        record = {
            "submission_id": submission_id,
            "input_type": input_type,
            "category": category,
            "urgency_rating": urgency,
            "summary_en": summary,
            "latitude": lat,
            "longitude": lng,
            "submitted_at": datetime.now(timezone.utc).isoformat(),
        }
        await sub_ref.set(record)
        await user_ref.update({"submission_count": firestore.Increment(1)})
    except Exception as e:
        log.warning("firestore_submission_track_failed", error=str(e), uid=firebase_uid)


# ── Request / Response models ─────────────────────────────────────────


class SubmissionResponse(BaseModel):
    submission_id: str
    status: str = "processing"
    category: str | None = None
    urgency_rating: int | None = None
    summary_en: str | None = None
    message: str = "Submission received and is being processed"


# ── Helpers ───────────────────────────────────────────────────────────


def _new_submission_id() -> str:
    return f"sub-{uuid.uuid4().hex[:12]}"


ALLOWED_AUDIO_TYPES = {
    "audio/webm",
    "audio/ogg",
    "audio/mpeg",
    "audio/wav",
    "audio/mp4",
    "audio/aac",
    "audio/flac",
}
ALLOWED_IMAGE_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
}
MAX_AUDIO_BYTES = 10 * 1024 * 1024  # 10MB
MAX_IMAGE_BYTES = 5 * 1024 * 1024  # 5MB
MAX_TEXT_CHARS = 2000


# ── Text Submission ───────────────────────────────────────────────────


class TextSubmissionRequest(BaseModel):
    text: str = Field(min_length=5, max_length=MAX_TEXT_CHARS)
    language_code: str | None = Field(
        default=None,
        description="BCP-47 language code (e.g. hi-IN, kn-IN). Auto-detected if omitted.",
    )
    constituency_id: str | None = None
    latitude: float | None = None
    longitude: float | None = None


@router.post(
    "/text", response_model=SubmissionResponse, status_code=status.HTTP_202_ACCEPTED
)
async def submit_text(
    request: TextSubmissionRequest,
    background_tasks: BackgroundTasks,
    settings: Annotated[Settings, Depends(get_settings)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    translation: Annotated[TranslationService, Depends(get_translation_service)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    pubsub: Annotated[PubSubService, Depends(get_pubsub_service)],
    authorization: Annotated[str | None, Header()] = None,
):
    submission_id = _new_submission_id()
    constituency_id = request.constituency_id or settings.constituency_id

    log.info(
        "intake_text_received", submission_id=submission_id, chars=len(request.text)
    )

    try:
        # Translate to English if needed
        translated, source_lang = await translation.translate_to_english(
            request.text,
            source_language=request.language_code,
        )

        # Extract structured data via Gemini
        grievance, latency_ms = await gemini.extract_from_text(
            text=request.text,
            translated_text=translated,
        )
        grievance.source_language = source_lang

        # Override lat/lon if provided by client (GPS from app)
        if request.latitude is not None:
            grievance.latitude = request.latitude
        if request.longitude is not None:
            grievance.longitude = request.longitude

        # Stream into BigQuery
        await bq.insert_grievance(
            submission_id=submission_id,
            grievance=grievance,
            input_type="text",
            raw_gcs_uri="",  # No media for text
            translated_text=translated,
            constituency_id=constituency_id,
            gemini_model=settings.gemini_model,
            processing_latency_ms=latency_ms,
        )

        # Publish async event
        background_tasks.add_task(
            pubsub.publish_grievance_submitted,
            submission_id, constituency_id, "text",
        )
        # Track in Firestore for user submission history
        firebase_uid = _firebase_uid_from_token(authorization)
        if firebase_uid:
            background_tasks.add_task(
                _track_submission, settings, firebase_uid, submission_id,
                "text", grievance.category.value, grievance.urgency_rating,
                grievance.summary_en, request.latitude, request.longitude,
            )

        return SubmissionResponse(
            submission_id=submission_id,
            status="processed",
            category=grievance.category.value,
            urgency_rating=grievance.urgency_rating,
            summary_en=grievance.summary_en,
        )

    except Exception as exc:
        log.error("intake_text_failed", submission_id=submission_id, error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Processing failed: {str(exc)}",
        )


# ── Audio Submission ──────────────────────────────────────────────────


@router.post(
    "/audio", response_model=SubmissionResponse, status_code=status.HTTP_202_ACCEPTED
)
async def submit_audio(
    background_tasks: BackgroundTasks,
    settings: Annotated[Settings, Depends(get_settings)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    speech: Annotated[SpeechService, Depends(get_speech_service)],
    translation: Annotated[TranslationService, Depends(get_translation_service)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    storage: Annotated[StorageService, Depends(get_storage_service)],
    pubsub: Annotated[PubSubService, Depends(get_pubsub_service)],
    audio_file: UploadFile = File(...),
    language_code: str = Form(default="auto"),
    constituency_id: str = Form(default=None),
    latitude: float | None = Form(default=None),
    longitude: float | None = Form(default=None),
    authorization: Annotated[str | None, Header()] = None,
):
    submission_id = _new_submission_id()
    constituency_id = constituency_id or settings.constituency_id

    # Validate content type
    if audio_file.content_type not in ALLOWED_AUDIO_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported audio type: {audio_file.content_type}. Allowed: {ALLOWED_AUDIO_TYPES}",
        )

    audio_bytes = await audio_file.read()
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Audio exceeds {MAX_AUDIO_BYTES // 1024 // 1024}MB limit",
        )

    log.info(
        "intake_audio_received", submission_id=submission_id, bytes=len(audio_bytes)
    )

    try:
        # Upload raw audio to GCS
        gcs_uri = await storage.upload_audio(
            audio_bytes=audio_bytes,
            submission_id=submission_id,
            constituency_id=constituency_id,
            content_type=audio_file.content_type,
        )

        # Transcribe
        transcript, detected_lang = await speech.transcribe(
            audio_bytes=audio_bytes,
            language_code=language_code,
        )

        if not transcript:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Could not transcribe audio — please speak clearly or try text submission",
            )

        # Translate to English
        translated, _ = await translation.translate_to_english(
            transcript, source_language=detected_lang
        )

        # Gemini extraction
        grievance, latency_ms = await gemini.extract_from_text(
            text=transcript,
            translated_text=translated,
        )
        grievance.source_language = detected_lang

        if latitude is not None:
            grievance.latitude = latitude
        if longitude is not None:
            grievance.longitude = longitude

        # Stream to BigQuery
        await bq.insert_grievance(
            submission_id=submission_id,
            grievance=grievance,
            input_type="audio",
            raw_gcs_uri=gcs_uri,
            translated_text=translated,
            constituency_id=constituency_id,
            gemini_model=settings.gemini_model,
            processing_latency_ms=latency_ms,
        )

        background_tasks.add_task(
            pubsub.publish_grievance_submitted,
            submission_id, constituency_id, "audio",
        )
        firebase_uid = _firebase_uid_from_token(authorization)
        if firebase_uid:
            background_tasks.add_task(
                _track_submission, settings, firebase_uid, submission_id,
                "audio", grievance.category.value, grievance.urgency_rating,
                grievance.summary_en, latitude, longitude,
            )

        return SubmissionResponse(
            submission_id=submission_id,
            status="processed",
            category=grievance.category.value,
            urgency_rating=grievance.urgency_rating,
            summary_en=grievance.summary_en,
        )

    except HTTPException:
        raise
    except Exception as exc:
        log.error("intake_audio_failed", submission_id=submission_id, error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Audio processing failed: {str(exc)}",
        )


# ── Image Submission ──────────────────────────────────────────────────


@router.post(
    "/image", response_model=SubmissionResponse, status_code=status.HTTP_202_ACCEPTED
)
async def submit_image(
    background_tasks: BackgroundTasks,
    settings: Annotated[Settings, Depends(get_settings)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    storage: Annotated[StorageService, Depends(get_storage_service)],
    pubsub: Annotated[PubSubService, Depends(get_pubsub_service)],
    image_file: UploadFile = File(...),
    constituency_id: str = Form(default=None),
    latitude: float | None = Form(default=None),
    longitude: float | None = Form(default=None),
    caption: str | None = Form(default=None),
    authorization: Annotated[str | None, Header()] = None,
):
    submission_id = _new_submission_id()
    constituency_id = constituency_id or settings.constituency_id

    if image_file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type: {image_file.content_type}",
        )

    image_bytes = await image_file.read()
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image exceeds {MAX_IMAGE_BYTES // 1024 // 1024}MB limit",
        )

    log.info(
        "intake_image_received", submission_id=submission_id, bytes=len(image_bytes)
    )

    try:
        # Upload to GCS
        gcs_uri = await storage.upload_image(
            image_bytes=image_bytes,
            submission_id=submission_id,
            constituency_id=constituency_id,
            content_type=image_file.content_type,
        )

        # Gemini multimodal extraction
        grievance, latency_ms = await gemini.extract_from_image(
            image_bytes=image_bytes,
            mime_type=image_file.content_type,
        )

        # GPS from device if provided — overrides Gemini's guess
        if latitude is not None:
            grievance.latitude = latitude
        if longitude is not None:
            grievance.longitude = longitude

        translated_text = caption or grievance.summary_en

        await bq.insert_grievance(
            submission_id=submission_id,
            grievance=grievance,
            input_type="image",
            raw_gcs_uri=gcs_uri,
            translated_text=translated_text,
            constituency_id=constituency_id,
            gemini_model=settings.gemini_model,
            processing_latency_ms=latency_ms,
        )

        background_tasks.add_task(
            pubsub.publish_grievance_submitted,
            submission_id, constituency_id, "image",
        )
        firebase_uid = _firebase_uid_from_token(authorization)
        if firebase_uid:
            background_tasks.add_task(
                _track_submission, settings, firebase_uid, submission_id,
                "image", grievance.category.value, grievance.urgency_rating,
                grievance.summary_en, latitude, longitude,
            )

        return SubmissionResponse(
            submission_id=submission_id,
            status="processed",
            category=grievance.category.value,
            urgency_rating=grievance.urgency_rating,
            summary_en=grievance.summary_en,
        )

    except HTTPException:
        raise
    except Exception as exc:
        log.error("intake_image_failed", submission_id=submission_id, error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Image processing failed: {str(exc)}",
        )
