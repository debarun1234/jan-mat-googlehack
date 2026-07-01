"""
Cloud Speech-to-Text service — Indic language audio transcription.

Supports: Hindi (hi-IN), Kannada (kn-IN), Tamil (ta-IN), Telugu (te-IN),
          Bengali (bn-IN), Marathi (mr-IN), Gujarati (gu-IN), English (en-IN)
"""

import structlog
from google.cloud import speech_v1 as speech
from tenacity import retry, stop_after_attempt, wait_exponential

log = structlog.get_logger()

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


class SpeechService:
    def __init__(self):
        self._client: speech.SpeechClient | None = None

    def _get_client(self) -> speech.SpeechClient:
        if self._client is None:
            self._client = speech.SpeechClient()
        return self._client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=8),
        reraise=True,
    )
    async def transcribe(
        self,
        audio_bytes: bytes,
        language_code: str = "hi-IN",
        audio_encoding: speech.RecognitionConfig.AudioEncoding = speech.RecognitionConfig.AudioEncoding.WEBM_OPUS,
        sample_rate_hertz: int = 48000,
    ) -> tuple[str, str]:
        """
        Transcribe audio bytes to text.

        Returns (transcript_text, detected_language_code).
        Uses multi-language detection if language_code is 'auto'.
        """
        client = self._get_client()

        if language_code == "auto":
            # Primary = Hindi, alternatives = rest of supported languages
            config = speech.RecognitionConfig(
                encoding=audio_encoding,
                sample_rate_hertz=sample_rate_hertz,
                language_code="hi-IN",
                alternative_language_codes=SUPPORTED_LANGUAGES[1:],
                enable_automatic_punctuation=True,
                model="latest_long",
            )
        else:
            config = speech.RecognitionConfig(
                encoding=audio_encoding,
                sample_rate_hertz=sample_rate_hertz,
                language_code=language_code,
                alternative_language_codes=[
                    lc for lc in SUPPORTED_LANGUAGES if lc != language_code
                ],
                enable_automatic_punctuation=True,
                model="latest_long",
            )

        audio = speech.RecognitionAudio(content=audio_bytes)

        # Use synchronous recognize for short clips (<60s), long_running for longer
        if len(audio_bytes) < 2 * 1024 * 1024:  # <2MB → sync
            response = client.recognize(config=config, audio=audio)
        else:
            operation = client.long_running_recognize(config=config, audio=audio)
            response = operation.result(timeout=120)

        if not response.results:
            log.warning("speech_no_results", bytes=len(audio_bytes), lang=language_code)
            return "", language_code

        # Take highest-confidence alternative from first result
        best = response.results[0].alternatives[0]
        detected_lang = getattr(response.results[0], "language_code", language_code)

        log.info(
            "speech_transcription",
            chars=len(best.transcript),
            confidence=round(best.confidence, 3),
            detected_lang=detected_lang,
        )
        return best.transcript, detected_lang


_speech_service: SpeechService | None = None


def get_speech_service() -> SpeechService:
    global _speech_service
    if _speech_service is None:
        _speech_service = SpeechService()
    return _speech_service
