"""
Gemini API client for structured AI inference.
Implements retry logic, schema validation, and structured output.

Uses the new google-genai SDK (replaces deprecated vertexai.generative_models
and google-generativeai). Both Vertex AI and AI Studio modes are supported
through the same client interface.

Authentication strategy (in priority order):
  1. GEMINI_API_KEY env var → AI Studio endpoint (genai.Client(api_key=...))
  2. No key → Vertex AI with Application Default Credentials
     (Cloud Run service account must have roles/aiplatform.user)
"""

import json
import logging
import time
from typing import Dict, Any, Optional

from google import genai
from google.genai import types
from google.api_core import exceptions

from app.config.settings import get_settings
from app.utils.errors import AIError, ErrorCode


logger = logging.getLogger(__name__)


class GeminiClient:
    """Production Gemini client with structured output (google-genai SDK)."""

    def __init__(self):
        self.settings = get_settings()
        self._use_vertex = not bool(self.settings.ai.gemini_api_key)

        if self._use_vertex:
            # Vertex AI — uses Cloud Run service account (ADC), no key needed
            logger.info(
                "GEMINI_API_KEY not set — using Vertex AI via google-genai SDK "
                f"(project={self.settings.cloud.gcp_project_id}, location=us-central1)"
            )
            self._client = genai.Client(
                vertexai=True,
                project=self.settings.cloud.gcp_project_id,
                location="us-central1",  # Gemini served globally from us-central1
            )
        else:
            # AI Studio / Gemini API — uses explicit API key
            logger.info("Using AI Studio endpoint with GEMINI_API_KEY")
            self._client = genai.Client(api_key=self.settings.ai.gemini_api_key)

        self._model = self.settings.ai.gemini_model
        self.call_count = 0
        self.error_count = 0

    def _build_system_prompt(self) -> str:
        """Build system prompt with constraints."""
        return """You are a data classification AI for citizen grievances.
Your task is to analyze citizen feedback and extract structured information.

IMPORTANT: You MUST respond ONLY with valid JSON, no markdown, no explanations.

Return a JSON object with exactly these fields:
{
    "category": "Education|Health|Roads|Water|Sanitation|Electricity|Transport|Governance|Other",
    "priority": "Low|Medium|High|Critical",
    "sentiment": "Negative|Neutral|Positive",
    "summary_en": "Brief English summary (1-2 sentences)",
    "confidence_score": 0.0-1.0
}

Rules:
1. category: Classify the grievance type
2. priority: Set based on urgency and impact
3. sentiment: Emotional tone of the complaint
4. summary_en: Concise summary in English (10-500 characters)
5. confidence_score: Your confidence in this classification (0-1)

Never include additional fields, markdown formatting, or explanations.
"""

    def _build_user_prompt(self, text: str) -> str:
        """Build user prompt with text."""
        return f"""Analyze this citizen grievance and return only JSON:

{text}

Remember: ONLY return JSON, no other text."""

    def _parse_response(self, response_text: str) -> str:
        """
        Parse Gemini response, extracting JSON if necessary.

        Returns:
            JSON string

        Raises:
            AIError: If response cannot be parsed
        """
        try:
            json.loads(response_text)
            return response_text
        except json.JSONDecodeError:
            pass

        import re

        json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
        if json_match:
            json_str = json_match.group(0)
            try:
                json.loads(json_str)
                return json_str
            except json.JSONDecodeError:
                pass

        raise AIError(
            message="Could not extract valid JSON from Gemini response",
            error_code=ErrorCode.AI_INVALID_RESPONSE,
            details={"response": response_text[:500]},
        )

    def infer(
        self, text: str, request_id: Optional[str] = None, timeout: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Call Gemini API for structured inference (synchronous).

        Designed to run inside a thread pool executor (FastAPI's
        loop.run_in_executor) so it does not block the event loop.

        Args:
            text: Text to analyze
            request_id: Request ID for tracking
            timeout: Unused — kept for API compatibility

        Returns:
            Parsed JSON response dict

        Raises:
            AIError: If API call fails
        """
        try:
            self.call_count += 1

            system_prompt = self._build_system_prompt()
            user_prompt = self._build_user_prompt(text)

            start_time = time.time()
            response = self._client.models.generate_content(
                model=self._model,
                contents=user_prompt,
                config=types.GenerateContentConfig(
                    system_instruction=system_prompt,
                    temperature=self.settings.ai.gemini_temperature,
                    max_output_tokens=self.settings.ai.gemini_max_tokens,
                    response_mime_type="application/json",
                ),
            )
            duration_ms = (time.time() - start_time) * 1000

            json_response = self._parse_response(response.text)
            parsed = json.loads(json_response)

            logger.info(
                "Gemini inference completed",
                extra={
                    "request_id": request_id,
                    "duration_ms": round(duration_ms, 2),
                    "model": self._model,
                },
            )
            return parsed

        except exceptions.InvalidArgument as e:
            self.error_count += 1
            raise AIError(
                message=f"Invalid Gemini request: {str(e)}",
                error_code=ErrorCode.AI_API_ERROR,
                request_id=request_id,
                original_exception=e,
            )

        except exceptions.ResourceExhausted as e:
            self.error_count += 1
            raise AIError(
                message="Gemini API quota exceeded",
                error_code=ErrorCode.AI_QUOTA_EXCEEDED,
                request_id=request_id,
                original_exception=e,
                retry_eligible=True,
            )

        except AIError:
            raise

        except Exception as e:
            self.error_count += 1
            raise AIError(
                message=f"Gemini API error: {str(e)}",
                error_code=ErrorCode.AI_API_ERROR,
                request_id=request_id,
                original_exception=e,
            )

    def get_stats(self) -> Dict[str, Any]:
        """Get API call statistics."""
        return {
            "total_calls": self.call_count,
            "total_errors": self.error_count,
            "error_rate": self.error_count / self.call_count
            if self.call_count > 0
            else 0,
            "success_count": self.call_count - self.error_count,
        }


def get_gemini_client() -> GeminiClient:
    """Get or create Gemini client singleton."""
    if not hasattr(get_gemini_client, "_instance"):
        get_gemini_client._instance = GeminiClient()
    return get_gemini_client._instance
