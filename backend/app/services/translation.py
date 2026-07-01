"""
Cloud Translation API service — normalize Indic language text to English.

Used between Speech-to-Text output and Gemini extraction so that Gemini
always receives English text (reduces token cost and improves accuracy).
"""

import structlog
from google.cloud import translate_v2 as translate
from tenacity import retry, stop_after_attempt, wait_exponential

log = structlog.get_logger()


class TranslationService:
    def __init__(self):
        self._client: translate.Client | None = None

    def _get_client(self) -> translate.Client:
        if self._client is None:
            self._client = translate.Client()
        return self._client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=6),
        reraise=True,
    )
    async def translate_to_english(
        self,
        text: str,
        source_language: str | None = None,
    ) -> tuple[str, str]:
        """
        Translate text to English.

        Args:
            text: Text to translate.
            source_language: BCP-47 code (e.g. 'hi', 'kn'). If None, auto-detected.

        Returns:
            (translated_text, detected_source_language)
        """
        client = self._get_client()

        # Skip translation if already English
        if source_language and source_language.startswith("en"):
            return text, source_language

        kwargs = {"target_language": "en"}
        if source_language:
            # Strip region suffix: 'hi-IN' → 'hi'
            kwargs["source_language"] = source_language.split("-")[0]

        result = client.translate(text, **kwargs)

        translated = result["translatedText"]
        detected = result.get("detectedSourceLanguage", source_language or "unknown")

        log.info(
            "translation_complete",
            source_lang=detected,
            input_chars=len(text),
            output_chars=len(translated),
        )
        return translated, detected

    async def detect_language(self, text: str) -> str:
        """Detect the language of a text. Returns BCP-47 language code."""
        client = self._get_client()
        result = client.detect_language(text)
        return result.get("language", "unknown")


_translation_service: TranslationService | None = None


def get_translation_service() -> TranslationService:
    global _translation_service
    if _translation_service is None:
        _translation_service = TranslationService()
    return _translation_service
