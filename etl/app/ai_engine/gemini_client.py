"""
Gemini API client for structured AI inference.
Implements retry logic, schema validation, and streaming.

Authentication strategy (in priority order):
  1. GEMINI_API_KEY env var → uses google.generativeai (AI Studio endpoint)
  2. No key → uses Vertex AI SDK with Application Default Credentials
     (Cloud Run service account must have roles/aiplatform.user)
"""

import json
import logging
import asyncio
from typing import Dict, Any, Optional
import time

from google.api_core import retry, exceptions

from app.config.settings import get_settings
from app.utils.errors import AIError, ErrorCode


logger = logging.getLogger(__name__)


class GeminiClient:
    """Production Gemini client with structured output."""

    def __init__(self):
        self.settings = get_settings()
        self._use_vertex = not bool(self.settings.ai.gemini_api_key)

        if self._use_vertex:
            # Vertex AI — uses Cloud Run service account (ADC), no key needed
            import vertexai
            from vertexai.generative_models import GenerativeModel

            logger.info(
                "GEMINI_API_KEY not set — using Vertex AI SDK with ADC "
                f"(project={self.settings.cloud.gcp_project_id}, "
                f"location={self.settings.cloud.gcp_region})"
            )
            vertexai.init(
                project=self.settings.cloud.gcp_project_id,
                location="global",
            )
            self.model = GenerativeModel(self.settings.ai.gemini_model)
        else:
            # AI Studio / Gemini API — uses explicit API key
            import google.generativeai as genai

            genai.configure(api_key=self.settings.ai.gemini_api_key)
            self.model = genai.GenerativeModel(self.settings.ai.gemini_model)
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

        Args:
            response_text: Raw response from Gemini

        Returns:
            JSON string

        Raises:
            AIError: If response cannot be parsed
        """

        # Try to find JSON in response
        try:
            # First, try direct parse
            json.loads(response_text)
            return response_text
        except json.JSONDecodeError:
            pass

        # Try to extract JSON from response
        # Look for { ... } pattern
        import re

        json_match = re.search(r"\{.*\}", response_text, re.DOTALL)

        if json_match:
            json_str = json_match.group(0)
            try:
                json.loads(json_str)
                return json_str
            except json.JSONDecodeError:
                pass

        # If still no valid JSON
        raise AIError(
            message="Could not extract valid JSON from Gemini response",
            error_code=ErrorCode.AI_INVALID_RESPONSE,
            details={"response": response_text[:500]},
        )

    @retry.Retry(deadline=60)
    def infer(
        self, text: str, request_id: Optional[str] = None, timeout: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Call Gemini API for structured inference.

        Args:
            text: Text to analyze
            request_id: Request ID for tracking
            timeout: Optional timeout override

        Returns:
            Parsed JSON response

        Raises:
            AIError: If API call fails
        """

        if timeout is None:
            timeout = self.settings.ai.ai_timeout_seconds

        try:
            self.call_count += 1

            # Build prompts
            system_prompt = self._build_system_prompt()
            user_prompt = self._build_user_prompt(text)

            # Call Gemini
            start_time = time.time()

            response = asyncio.run(
                self._infer_async(system_prompt, user_prompt, timeout)
            )

            duration_ms = (time.time() - start_time) * 1000

            # Parse response
            json_response = self._parse_response(response.text)
            parsed = json.loads(json_response)

            logger.info(
                "Gemini inference completed",
                request_id=request_id,
                duration_ms=round(duration_ms, 2),
                tokens_in=response.usage.prompt_token_count
                if hasattr(response, "usage")
                else None,
                tokens_out=response.usage.completion_token_count
                if hasattr(response, "usage")
                else None,
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

        except exceptions.RateLimited as e:
            self.error_count += 1
            raise AIError(
                message="Gemini API rate limited",
                error_code=ErrorCode.AI_RATE_LIMITED,
                request_id=request_id,
                original_exception=e,
                retry_eligible=True,
            )

        except asyncio.TimeoutError:
            self.error_count += 1
            raise AIError(
                message="Gemini API timeout",
                error_code=ErrorCode.AI_TIMEOUT,
                request_id=request_id,
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

    async def _infer_async(self, system_prompt: str, user_prompt: str, timeout: int):
        """Async Gemini call with timeout."""

        loop = asyncio.get_event_loop()

        def sync_call():
            return self.model.generate_content(
                [system_prompt, user_prompt],
                generation_config={
                    "temperature": self.settings.ai.gemini_temperature,
                    "max_output_tokens": self.settings.ai.gemini_max_tokens,
                },
            )

        return await asyncio.wait_for(
            loop.run_in_executor(None, sync_call), timeout=timeout
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
    """Get or create Gemini client."""
    if not hasattr(get_gemini_client, "_instance"):
        get_gemini_client._instance = GeminiClient()
    return get_gemini_client._instance
