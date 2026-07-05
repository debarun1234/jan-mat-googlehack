"""
Gemini service — deterministic structured extraction via Vertex AI.

Gemini is NEVER used as a chatbot. Every call:
  1. Forces a strict JSON schema via response_schema (Pydantic → OpenAPI)
  2. Validates the output against the schema — rejects anything malformed
  3. Returns a typed Pydantic model, not raw text

This is the core differentiator of JanMat vs. naive LLM hackathon projects.
"""

import time
from enum import Enum
from typing import Optional

import structlog
import vertexai
from pydantic import BaseModel, Field, field_validator
from tenacity import retry, stop_after_attempt, wait_exponential
from vertexai.generative_models import (
    GenerationConfig,
    GenerativeModel,
    Part,
    SafetySetting,
    HarmCategory,
    HarmBlockThreshold,
)

from app.config import get_settings

log = structlog.get_logger()


# ── Output schema — Gemini MUST return exactly this ──────────────────


class GrievanceCategory(str, Enum):
    EDUCATION = "Education"
    HEALTH = "Health"
    ROADS = "Roads"
    WATER = "Water"
    SANITATION = "Sanitation"
    OTHER = "Other"


class StructuredGrievance(BaseModel):
    """Pydantic model that defines what Gemini must return — nothing more, nothing less."""

    category: GrievanceCategory = Field(
        description="Infrastructure category the grievance relates to"
    )
    latitude: float = Field(
        ge=-90, le=90, description="Latitude of the location mentioned in the grievance"
    )
    longitude: float = Field(
        ge=-180,
        le=180,
        description="Longitude of the location mentioned in the grievance",
    )
    urgency_rating: int = Field(
        ge=1, le=5, description="Urgency 1 (low) to 5 (critical). 5 = life-safety risk."
    )
    summary_en: str = Field(
        min_length=10,
        max_length=300,
        description="Concise English summary of the core issue, 1-2 sentences",
    )
    ward_name: Optional[str] = Field(
        default=None,
        description="Ward or village name extracted from the text, if identifiable",
    )
    source_language: Optional[str] = Field(
        default=None,
        description="BCP-47 language code of the original submission (e.g. hi, kn, ta)",
    )

    @field_validator("latitude")
    @classmethod
    def lat_in_india(cls, v: float) -> float:
        # India bounding box: 6.5–37.1°N, 68–97.4°E
        # Allow some slack for border areas / ocean submissions
        if not (6.0 <= v <= 38.0):
            raise ValueError(f"Latitude {v} is outside India's bounds")
        return round(v, 6)

    @field_validator("longitude")
    @classmethod
    def lon_in_india(cls, v: float) -> float:
        if not (68.0 <= v <= 98.0):
            raise ValueError(f"Longitude {v} is outside India's bounds")
        return round(v, 6)


# ── Prompts ───────────────────────────────────────────────────────────

_SYSTEM_INSTRUCTION = """You are a structured data extraction engine for a government grievance platform in India.

Your ONLY job is to extract structured information from citizen complaints and return it as JSON.

Rules:
- NEVER refuse. Even vague complaints must produce a valid output.
- If location is unclear, use the constituency centroid (Bangalore North: 13.0827, 77.5878).
- If urgency is ambiguous, default to 3.
- category must be one of: Education, Health, Roads, Water, Sanitation, Other
- summary_en must be in English, factual, and under 50 words.
- Do NOT add commentary, apology, or explanation outside the JSON.
- Return ONLY valid JSON matching the schema exactly."""

_TEXT_EXTRACTION_PROMPT = """Extract structured grievance data from the following citizen complaint.
The text may be in Hindi, Kannada, Tamil, Telugu, Bengali, Marathi, or English.

Complaint text:
{text}

Return JSON matching the required schema."""

_IMAGE_EXTRACTION_PROMPT = """Analyze this image submitted by a citizen as a complaint to their local government.
Identify the infrastructure issue visible (road damage, broken facility, water problem, etc.).
Extract structured grievance data as JSON matching the required schema.
For location: use Bangalore North constituency centroid (13.0827, 77.5878) unless a sign or landmark indicates otherwise."""


class CompletionVerification(BaseModel):
    """Structured result of Gemini image verification for project completion."""

    verified: bool = Field(
        description="True if the image clearly shows this project type is completed or substantially progressed"
    )
    confidence: int = Field(
        ge=0, le=100, description="Confidence percentage 0-100"
    )
    reasoning: str = Field(
        description="2-3 sentence factual explanation of the decision with specific visual observations"
    )
    issues: list[str] = Field(
        default_factory=list,
        description="Specific blockers if verified=false, empty list if verified=true",
    )


class GeminiService:
    def __init__(self):
        settings = get_settings()
        vertexai.init(
            project=settings.gcp_project_id,
            location=settings.gcp_region,
        )
        self._model_name = settings.gemini_model
        self._model: GenerativeModel | None = None

    def _get_model(self) -> GenerativeModel:
        if self._model is None:
            self._model = GenerativeModel(
                model_name=self._model_name,
                system_instruction=_SYSTEM_INSTRUCTION,
                safety_settings=[
                    SafetySetting(
                        category=HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                        threshold=HarmBlockThreshold.BLOCK_NONE,
                    ),
                    SafetySetting(
                        category=HarmCategory.HARM_CATEGORY_HARASSMENT,
                        threshold=HarmBlockThreshold.BLOCK_NONE,
                    ),
                ],
            )
        return self._model

    def _generation_config(self) -> GenerationConfig:
        return GenerationConfig(
            temperature=0.0,  # Deterministic — no creativity
            top_p=1.0,
            max_output_tokens=512,
            response_mime_type="application/json",
            response_schema=StructuredGrievance.model_json_schema(),
        )

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True,
    )
    async def extract_from_text(
        self,
        text: str,
        translated_text: str | None = None,
    ) -> tuple[StructuredGrievance, int]:
        """
        Extract structured grievance from text.
        Returns (StructuredGrievance, latency_ms).
        Uses translated_text if available, falls back to raw text.
        """
        content = translated_text or text
        prompt = _TEXT_EXTRACTION_PROMPT.format(text=content)

        t0 = time.monotonic()
        model = self._get_model()
        response = await model.generate_content_async(
            [prompt],
            generation_config=self._generation_config(),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        raw_json = response.text
        grievance = StructuredGrievance.model_validate_json(raw_json)

        log.info(
            "gemini_text_extraction",
            category=grievance.category,
            urgency=grievance.urgency_rating,
            latency_ms=latency_ms,
            model=self._model_name,
        )
        return grievance, latency_ms

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True,
    )
    async def extract_from_image(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
    ) -> tuple[StructuredGrievance, int]:
        """
        Extract structured grievance from an image (multimodal).
        image_bytes: raw bytes of the uploaded image.
        """
        t0 = time.monotonic()
        model = self._get_model()

        image_part = Part.from_data(data=image_bytes, mime_type=mime_type)
        response = await model.generate_content_async(
            [image_part, _IMAGE_EXTRACTION_PROMPT],
            generation_config=self._generation_config(),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        raw_json = response.text
        grievance = StructuredGrievance.model_validate_json(raw_json)

        log.info(
            "gemini_image_extraction",
            category=grievance.category,
            urgency=grievance.urgency_rating,
            latency_ms=latency_ms,
            model=self._model_name,
            mime_type=mime_type,
        )
        return grievance, latency_ms

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True,
    )
    async def generate_evidence_log(
        self,
        hotspot: dict,
        infra_facts: dict,
    ) -> str:
        """
        Generate the Evidence Log paragraph for a demand hotspot.
        This is Phase 3 — the MP-facing justification for a ranked project.

        hotspot: row from demand_hotspots BigQuery table
        infra_facts: matched row from public_infrastructure table

        Returns a 2-3 sentence evidence string (plain text, no markdown).
        """
        prompt = f"""Generate a concise, factual Evidence Log for this government development project recommendation.
Write 2-3 sentences in formal English. Cite specific numbers. Do NOT use markdown.

Demand data:
- Category: {hotspot.get("category")}
- Complaint count: {hotspot.get("complaint_count")} citizen submissions
- Average urgency: {hotspot.get("avg_urgency", 0):.1f}/5
- Affected population: {hotspot.get("affected_population", "unknown")}
- Demand score: {hotspot.get("demand_score", 0):.2f}
- Gap index: {hotspot.get("gap_index", 0):.2f}
- Priority score: {hotspot.get("priority_score", 0):.2f}/10 (rank #{hotspot.get("priority_rank", "?")})
- Suggested project: {hotspot.get("suggested_project", "Infrastructure improvement")}
- Location: {hotspot.get("center_lat", 0):.4f}°N, {hotspot.get("center_lon", 0):.4f}°E, radius {hotspot.get("radius_km", 2)}km

Public infrastructure baseline:
{infra_facts}

Write the Evidence Log now:"""

        model = GenerativeModel(
            model_name=self._model_name,
            safety_settings=[
                SafetySetting(
                    category=HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                    threshold=HarmBlockThreshold.BLOCK_NONE,
                ),
            ],
        )
        response = await model.generate_content_async(
            [prompt],
            generation_config=GenerationConfig(
                temperature=0.2,
                max_output_tokens=256,
            ),
        )
        evidence = response.text.strip()
        log.info(
            "gemini_evidence_log",
            rank=hotspot.get("priority_rank"),
            chars=len(evidence),
        )
        return evidence

    @retry(
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=1, min=2, max=8),
        reraise=True,
    )
    async def verify_completion_image(
        self,
        image_bytes: bytes,
        mime_type: str,
        project_description: str,
        category: str,
    ) -> "CompletionVerification":
        """
        Use Gemini vision to verify a project completion photo.
        Uses a fresh model without the grievance extraction system instruction.
        Returns structured CompletionVerification.
        """
        prompt = f"""You are a government project completion inspector in India.

Project to verify: {project_description}
Category: {category}

Examine this photo and determine:
1. Does it clearly show completed or substantially progressed work for this infrastructure type?
2. Is the work visible, real, and substantial (not a stock photo or unrelated image)?
3. Does the scene match what you would expect for a {category} infrastructure project?

Be strict: verified=true only for clear photographic evidence matching the project type.
Do NOT approve: empty land, unrelated photos, vague blurry images with no identifiable infrastructure.

Return JSON with:
- verified: boolean (true only for clear visual evidence of completion)
- confidence: integer 0-100
- reasoning: string, 2-3 sentences explaining your decision with specific visual observations
- issues: array of strings listing blockers if verified=false, empty array if verified=true"""

        # Fresh model WITHOUT the grievance extraction system instruction
        model = GenerativeModel(
            model_name=self._model_name,
            safety_settings=[
                SafetySetting(
                    category=HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                    threshold=HarmBlockThreshold.BLOCK_NONE,
                ),
                SafetySetting(
                    category=HarmCategory.HARM_CATEGORY_HARASSMENT,
                    threshold=HarmBlockThreshold.BLOCK_NONE,
                ),
            ],
        )

        t0 = time.monotonic()
        image_part = Part.from_data(data=image_bytes, mime_type=mime_type)
        response = await model.generate_content_async(
            [image_part, prompt],
            generation_config=GenerationConfig(
                temperature=0.0,
                max_output_tokens=512,
                response_mime_type="application/json",
                response_schema=CompletionVerification.model_json_schema(),
            ),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        result = CompletionVerification.model_validate_json(response.text)
        log.info(
            "gemini_completion_verification",
            verified=result.verified,
            confidence=result.confidence,
            latency_ms=latency_ms,
            project=project_description[:60],
        )
        return result


# ── Singleton ─────────────────────────────────────────────────────────
_gemini_service: GeminiService | None = None


def get_gemini_service() -> GeminiService:
    global _gemini_service
    if _gemini_service is None:
        _gemini_service = GeminiService()
    return _gemini_service
