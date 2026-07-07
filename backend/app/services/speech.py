"""
Audio transcription via Gemini (replaces Cloud Speech-to-Text).

Cloud STT was failing because:
  1. Flutter records .m4a (audio/mp4 / AAC) but STT was configured for WEBM_OPUS.
  2. Only the first speech segment was captured — longer recordings were truncated.

Gemini handles m4a natively, auto-detects any Indian language, and returns
the complete transcription in one shot with no segment limit.
"""

import asyncio
import json
import logging

from google import genai
from google.genai import types
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

log = logging.getLogger(__name__)

# BCP-47 codes for all supported Indic languages
SUPPORTED_LANGUAGES = [
    "hi-IN",  # Hindi
    "kn-IN",  # Kannada
    "ta-IN",  # Tamil
    "te-IN",  # Telugu
    "bn-IN",  # Bengali
    "mr-IN",  # Marathi
    "gu-IN",  # Gujarati
    "en-IN",  # Indian English
]

_SYSTEM_INSTRUCTION = """You are an expert audio transcription system for a government grievance platform in India.
Transcribe citizen voice complaints completely and accurately.

Rules:
- Capture EVERY word — do not summarize, paraphrase, or skip any content
- The recording may be in Hindi, Kannada, Tamil, Telugu, Bengali, Marathi, Gujarati, English, or a mix
- Preserve the speaker's exact words
- If background noise obscures a word, use [unclear] as a placeholder
- Return ONLY the JSON object specified — no markdown, no extra text
"""

_TRANSCRIPTION_PROMPT = """Transcribe this audio recording completely and accurately.

Return ONLY a JSON object with exactly these fields:
{
    "transcript": "complete verbatim transcription in the original language(s)",
    "detected_language": "BCP-47 code — one of: hi-IN, kn-IN, ta-IN, te-IN, bn-IN, mr-IN, gu-IN, en-IN",
    "confidence": 0.95
}

Transcribe every single word. Missing words = unusable grievance data."""


class SpeechService:
    """
    Audio transcription using Gemini multimodal.

    Supports m4a / mp4 / webm / ogg / wav / mp3 from the Flutter recorder.
    Handles mixed-language recordings common in Indian urban areas.
    """

    def __init__(self):
        settings = get_settings()
        api_key = getattr(settings, "gemini_api_key", None)
        if api_key:
            self._client = genai.Client(api_key=api_key)
            log.info("speech_service_init: AI Studio mode")
        else:
            self._client = genai.Client(
                vertexai=True,
                project=settings.gcp_project_id,
                location=settings.gemini_region,  # "global"
            )
            log.info(
                "speech_service_init: Vertex AI mode",
                extra={"project": settings.gcp_project_id, "location": settings.gemini_region},
            )
        self._model = settings.gemini_model  # gemini-3.1-flash-lite

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=8),
        reraise=True,
    )
    async def transcribe(
        self,
        audio_bytes: bytes,
        language_code: str = "auto",
        content_type: str = "audio/mp4",
        # Legacy Cloud STT params — kept for API compatibility, unused
        audio_encoding=None,
        sample_rate_hertz: int = 0,
    ) -> tuple[str, str]:
        """
        Transcribe audio bytes to text via Gemini.

        Args:
            audio_bytes: Raw audio file bytes (m4a / mp4 / webm / etc.)
            language_code: BCP-47 hint or "auto" for auto-detection.
            content_type: MIME type of audio_bytes (e.g. "audio/mp4").

        Returns:
            (transcript_text, detected_language_code)
        """
        # Normalise MIME — Gemini requires a specific audio/* type
        mime = self._normalise_mime(content_type)

        def _sync_call() -> str:
            response = self._client.models.generate_content(
                model=self._model,
                contents=[
                    types.Part.from_bytes(data=audio_bytes, mime_type=mime),
                    _TRANSCRIPTION_PROMPT,
                ],
                config=types.GenerateContentConfig(
                    system_instruction=_SYSTEM_INSTRUCTION,
                    temperature=0.0,
                    response_mime_type="application/json",
                ),
            )
            return response.text

        raw = await asyncio.get_event_loop().run_in_executor(None, _sync_call)

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            # Gemini returned plain text instead of JSON — use it as transcript
            log.warning("speech_json_parse_failed", raw_preview=raw[:300])
            return raw.strip(), language_code if language_code != "auto" else "en-IN"

        transcript = parsed.get("transcript", "").strip()
        detected = parsed.get(
            "detected_language",
            language_code if language_code != "auto" else "en-IN",
        )

        if not transcript:
            log.warning("speech_empty_transcript", bytes=len(audio_bytes), mime=mime)
            return "", detected

        log.info(
            "speech_transcription_complete",
            extra={
                "chars": len(transcript),
                "lang": detected,
                "confidence": parsed.get("confidence", 0.0),
                "model": self._model,
            },
        )
        return transcript, detected

    @staticmethod
    def _normalise_mime(content_type: str) -> str:
        """Map content-type strings to MIME types Gemini accepts for audio."""
        _MAP = {
            "audio/mp4": "audio/mp4",
            "audio/m4a": "audio/mp4",
            "audio/mpeg": "audio/mpeg",
            "audio/mp3": "audio/mpeg",
            "audio/webm": "audio/webm",
            "audio/ogg": "audio/ogg",
            "audio/wav": "audio/wav",
            "audio/x-wav": "audio/wav",
            "audio/flac": "audio/flac",
            "audio/aac": "audio/aac",
        }
        return _MAP.get(content_type.lower().split(";")[0].strip(), "audio/mp4")


_speech_service: SpeechService | None = None


def get_speech_service() -> SpeechService:
    global _speech_service
    if _speech_service is None:
        _speech_service = SpeechService()
    return _speech_service
