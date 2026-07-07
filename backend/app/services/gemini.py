"""
Gemini service — deterministic structured extraction via Vertex AI.

Uses the new google-genai SDK (replaces deprecated vertexai.generative_models).

Every call:
  1. Forces a strict JSON schema via response_schema (Pydantic model passed directly)
  2. Validates the output against the schema — rejects anything malformed
  3. Returns a typed Pydantic model, not raw text
"""

import time
from enum import Enum
from typing import Optional

import structlog
from google import genai
from google.genai import types
from pydantic import BaseModel, Field, field_validator
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

log = structlog.get_logger()

# ── Output schema — Gemini MUST return exactly this ───────────────────


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
    confidence: int = Field(ge=0, le=100, description="Confidence percentage 0-100")
    reasoning: str = Field(
        description="2-3 sentence factual explanation of the decision with specific visual observations"
    )
    issues: list[str] = Field(
        default_factory=list,
        description="Specific blockers if verified=false, empty list if verified=true",
    )


# ── Safety settings (reusable) ────────────────────────────────────────

_SAFETY_OFF = [
    types.SafetySetting(
        category="HARM_CATEGORY_DANGEROUS_CONTENT",
        threshold="BLOCK_NONE",
    ),
    types.SafetySetting(
        category="HARM_CATEGORY_HARASSMENT",
        threshold="BLOCK_NONE",
    ),
]


class GeminiService:
    def __init__(self):
        settings = get_settings()
        if settings.gemini_api_key:
            # AI Studio endpoint — uses GEMINI_API_KEY, no Vertex quota needed
            log.info("gemini_service_init", mode="ai_studio", model=settings.gemini_model)
            self._client = genai.Client(api_key=settings.gemini_api_key)
        else:
            # Vertex AI — uses Cloud Run service account (ADC), no key needed
            # gemini-3.1-flash-lite requires location="global" on Vertex
            log.info(
                "gemini_service_init",
                mode="vertex",
                project=settings.gcp_project_id,
                location=settings.gemini_region,
                model=settings.gemini_model,
            )
            self._client = genai.Client(
                vertexai=True,
                project=settings.gcp_project_id,
                location=settings.gemini_region,  # "global"
            )
        self._model = settings.gemini_model  # gemini-3.1-flash-lite

    def _extraction_config(self) -> types.GenerateContentConfig:
        return types.GenerateContentConfig(
            system_instruction=_SYSTEM_INSTRUCTION,
            temperature=0.0,
            top_p=1.0,
            max_output_tokens=512,
            response_mime_type="application/json",
            response_schema=StructuredGrievance,
            safety_settings=_SAFETY_OFF,
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
        """Extract structured grievance from text. Returns (grievance, latency_ms)."""
        content = translated_text or text
        prompt = _TEXT_EXTRACTION_PROMPT.format(text=content)

        t0 = time.monotonic()
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=prompt,
            config=self._extraction_config(),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        grievance = StructuredGrievance.model_validate_json(response.text)
        log.info(
            "gemini_text_extraction",
            category=grievance.category,
            urgency=grievance.urgency_rating,
            latency_ms=latency_ms,
            model=self._model,
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
        """Extract structured grievance from an image (multimodal)."""
        t0 = time.monotonic()

        image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=[image_part, _IMAGE_EXTRACTION_PROMPT],
            config=self._extraction_config(),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        grievance = StructuredGrievance.model_validate_json(response.text)
        log.info(
            "gemini_image_extraction",
            category=grievance.category,
            urgency=grievance.urgency_rating,
            latency_ms=latency_ms,
            model=self._model,
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
        """Generate the Evidence Log paragraph for a demand hotspot (Phase 3)."""
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

        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.2,
                max_output_tokens=256,
                safety_settings=_SAFETY_OFF,
            ),
        )
        evidence = response.text.strip()
        log.info(
            "gemini_evidence_log",
            rank=hotspot.get("priority_rank"),
            chars=len(evidence),
        )
        return evidence

    async def generate_project_title(
        self,
        hotspot: dict,
        complaint_summaries: list[str],
    ) -> str:
        """
        Generate a specific, actionable project title from real complaint data.
        Replaces the generic CASE-based titles (e.g. 'Road Repair and Paving')
        with context-aware names like 'Pothole Repair on MG Road Stretch'.
        """
        samples_text = "\n".join(f"- {s}" for s in complaint_summaries[:5]) if complaint_summaries else "No samples available"
        prompt = f"""You are a government project manager in India creating a development project title.

Category: {hotspot.get("category")}
Number of complaints: {hotspot.get("complaint_count")}
Location: {hotspot.get("center_lat", 0):.4f}°N, {hotspot.get("center_lon", 0):.4f}°E
Citizen complaint summaries:
{samples_text}

Write ONE specific, actionable project title (6–10 words). Be specific about the type of issue from the complaints.
Do NOT use generic phrases like "Infrastructure Improvement". Do NOT use markdown or punctuation at the end.
Output ONLY the title:"""

        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.3,
                    max_output_tokens=32,
                    safety_settings=_SAFETY_OFF,
                ),
            )
            title = response.text.strip().strip('"').strip("'")
            return title if title else hotspot.get("suggested_project", f"{hotspot.get('category')} Infrastructure Project")
        except Exception:
            return hotspot.get("suggested_project", f"{hotspot.get('category')} Infrastructure Project")

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
    ) -> CompletionVerification:
        """Use Gemini vision to verify a project completion photo."""
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
- verified: boolean
- confidence: integer 0-100
- reasoning: string, 2-3 sentences with specific visual observations
- issues: array of strings listing blockers if verified=false, empty array if verified=true"""

        image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
        t0 = time.monotonic()
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=[image_part, prompt],
            config=types.GenerateContentConfig(
                temperature=0.0,
                max_output_tokens=512,
                response_mime_type="application/json",
                response_schema=CompletionVerification,
                safety_settings=_SAFETY_OFF,
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

    @retry(
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=1, min=2, max=8),
        reraise=True,
    )
    async def analyze_complaint_clusters(
        self,
        clusters: list[dict],
        constituency_id: str,
    ) -> list[dict]:
        """
        Gemini analyses geographic complaint clusters and identifies the most
        critical areas requiring MP intervention.
        """
        if not clusters:
            return []

        cluster_text = "\n".join(
            [
                f"- Cell {i + 1}: lat={c['grid_lat']}, lng={c['grid_lng']} | "
                f"complaints={c['complaint_count']} | image_evidence={c['image_count']} | "
                f"avg_urgency={c['avg_urgency']}/5 | max_urgency={c['max_urgency']}/5 | "
                f"categories=[{c['categories']}] | "
                f"samples={c['sample_summaries'][:2]}"
                for i, c in enumerate(clusters)
            ]
        )

        prompt = f"""You are an AI decision-support system for a Member of Parliament in India.

Analyse the following geographic complaint clusters from constituency {constituency_id}
and identify the TOP 5 most critical areas requiring immediate government intervention.

Complaint clusters (each is a ~1 km grid cell, last 90 days):
{cluster_text}

Prioritise cells based on THREE factors in this order:
1. complaint_count — more citizens = broader community impact
2. image_count — photo evidence proves the problem exists and is verifiable
3. avg_urgency — higher citizen-rated urgency = more severe daily impact

For each of the top 5 areas return:
- grid_lat / grid_lng: exact coordinates from the input
- area_label: a short descriptive label inferred from coords and context
- urgency_level: "Critical" (avg≥4 or image_count≥5), "High" (avg≥3), or "Medium"
- complaint_count, image_count: from input
- top_categories: array of the most-reported categories in this cell
- ai_reasoning: 2-3 sentences explaining WHY this area is the priority (cite specific numbers)
- recommended_action: one concrete action the MP should take

Return a JSON object with an "areas" key containing an array of exactly 5 objects (fewer if fewer than 5 clusters exist)."""

        class AreaInsightSchema(BaseModel):
            grid_lat: float
            grid_lng: float
            area_label: str
            urgency_level: str
            complaint_count: int
            image_count: int
            top_categories: list[str]
            ai_reasoning: str
            recommended_action: str

        class InsightsResponse(BaseModel):
            areas: list[AreaInsightSchema]

        t0 = time.monotonic()
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.1,
                max_output_tokens=2048,
                response_mime_type="application/json",
                response_schema=InsightsResponse,
            ),
        )
        latency_ms = int((time.monotonic() - t0) * 1000)

        result = InsightsResponse.model_validate_json(response.text)
        log.info(
            "gemini_ai_insights",
            areas=len(result.areas),
            latency_ms=latency_ms,
            constituency=constituency_id,
        )
        return [a.model_dump() for a in result.areas]


# ── Singleton ─────────────────────────────────────────────────────────
_gemini_service: GeminiService | None = None


def get_gemini_service() -> GeminiService:
    global _gemini_service
    if _gemini_service is None:
        _gemini_service = GeminiService()
    return _gemini_service
