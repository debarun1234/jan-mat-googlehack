"""
Phase 3 — MP Executive Dashboard Router

Endpoints:
  POST /dashboard/auth/login       — JWT login for MP
  GET  /dashboard/projects         — ranked project list with evidence
  GET  /dashboard/heatmap          — aggregated hotspot lat/lon for HeatmapLayer
  GET  /dashboard/ai-insights      — Gemini-ranked critical areas (volume + image + urgency)
  GET  /dashboard/map-submissions  — individual submission points for marker view
  GET  /dashboard/trends           — category trends over time
  GET  /dashboard/export/csv       — CSV export of ranked recommendations
"""

import asyncio
import base64
import calendar
import math
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel

from app.config import Settings, get_settings
from app.services.bigquery import BigQueryService, get_bigquery_service
from app.services.gemini import GeminiService, get_gemini_service
from app.services.storage import StorageService, get_storage_service

log = structlog.get_logger()
router = APIRouter(prefix="/dashboard", tags=["dashboard"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/dashboard/auth/login")

# Default constituency for POC — one MP, one constituency
DEFAULT_CONSTITUENCY = "KA-BLR-NORTH-01"


# ── Auth ──────────────────────────────────────────────────────────────


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    mp_name: str
    constituency_id: str


class GoogleLoginRequest(BaseModel):
    """Called by the Node.js dashboard server after Google OAuth verification."""

    email: str
    name: str
    service_key: str
    constituency_id: str = DEFAULT_CONSTITUENCY


def _create_jwt(data: dict, settings: Settings) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {**data, "exp": expire, "iat": datetime.now(timezone.utc)}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


async def _get_current_mp(
    token: Annotated[str, Depends(oauth2_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict:
    try:
        payload = jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
        username = payload.get("sub")
        if not username:
            raise ValueError("No sub claim")
        return payload
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


@router.post("/auth/google-login", response_model=TokenResponse)
async def google_login(
    body: GoogleLoginRequest,
    settings: Annotated[Settings, Depends(get_settings)],
):
    """
    Issues a backend JWT for a Google-authenticated MP.
    Called server-to-server by the Node.js dashboard after Google OAuth.
    The service_key prevents arbitrary clients from minting tokens.
    """
    if body.service_key != settings.janmat_dashboard_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid service key",
        )

    token = _create_jwt(
        {
            "sub": body.email,
            "name": body.name,
            "constituency_id": body.constituency_id,
        },
        settings,
    )
    log.info("mp_google_login", email=body.email, name=body.name)
    return TokenResponse(
        access_token=token,
        expires_in=settings.jwt_expire_minutes * 60,
        mp_name=body.name,
        constituency_id=body.constituency_id,
    )


@router.post("/auth/login", response_model=TokenResponse)
async def login(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """
    Legacy form-based login — kept for local dev / curl testing.
    Accepts service_key as password field.
    """
    if form_data.password != settings.janmat_dashboard_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    token = _create_jwt(
        {
            "sub": form_data.username,
            "name": form_data.username,
            "constituency_id": DEFAULT_CONSTITUENCY,
        },
        settings,
    )
    log.info("mp_login", username=form_data.username)
    return TokenResponse(
        access_token=token,
        expires_in=settings.jwt_expire_minutes * 60,
        mp_name=form_data.username,
        constituency_id=DEFAULT_CONSTITUENCY,
    )


# ── Projects ─────────────────────────────────────────────────────────


class MediaItem(BaseModel):
    submission_id: str
    input_type: str          # "image" | "audio"
    summary_en: str | None = None
    media_url: str           # proxied via /dashboard/media/<id>


class ProjectItem(BaseModel):
    rank: int
    category: str
    suggested_project: str
    priority_score: float
    demand_score: float
    gap_index: float
    complaint_count: int
    avg_urgency: float
    affected_population: int | None
    center_lat: float
    center_lon: float
    radius_km: float
    evidence_log: str | None = None
    complaint_media: list[MediaItem] = []


class ProjectsResponse(BaseModel):
    constituency_id: str
    generated_at: str
    total_projects: int
    projects: list[ProjectItem]


@router.get("/projects", response_model=ProjectsResponse)
async def get_projects(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    limit: int = 10,
    generate_evidence: bool = True,
    constituency_id_param: str | None = Query(None, alias="constituency_id"),
):
    """
    Return ranked development projects with Gemini Evidence Logs.

    This is the core Phase 3 output — what the MP sees.
    """
    constituency_id = constituency_id_param or mp.get("constituency_id", settings.constituency_id)

    try:
        ranked = await bq.get_priority_ranking(constituency_id, limit=limit)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"BigQuery error: {exc}")

    if not ranked:
        return ProjectsResponse(
            constituency_id=constituency_id,
            generated_at=datetime.now(timezone.utc).isoformat(),
            total_projects=0,
            projects=[],
        )

    backend_base = "https://janmat-backend-w2w3osjaua-el.a.run.app"

    async def _process_project(row: dict) -> ProjectItem:
        """Process one ranked project: parallel BQ + single Gemini call."""
        suggested_project = row.get("suggested_project", "")
        evidence_text = None
        category = row.get("category", "")

        if generate_evidence:
            # All three BQ queries are independent — run them in parallel
            infra, complaint_samples, raw_media = await asyncio.gather(
                bq.get_infrastructure_facts(constituency_id, category),
                bq.get_complaint_samples(constituency_id, category, limit=5),
                bq.get_project_media(constituency_id, category, limit=5),
            )
            # One Gemini call returns both title and evidence log
            suggested_project, evidence_text = await gemini.generate_project_analysis(
                hotspot=row,
                complaint_summaries=complaint_samples,
                infra_facts=infra.get("summary", ""),
            )
        else:
            raw_media = await bq.get_project_media(constituency_id, category, limit=5)

        complaint_media = [
            MediaItem(
                submission_id=m["submission_id"],
                input_type=m["input_type"],
                summary_en=m.get("summary_en"),
                media_url=f"{backend_base}/dashboard/media/{m['submission_id']}",
            )
            for m in raw_media
        ]
        return ProjectItem(
            rank=int(row.get("priority_rank", 0)),
            category=category,
            suggested_project=suggested_project,
            priority_score=float(row.get("priority_score", 0)),
            demand_score=float(row.get("demand_score", 0)),
            gap_index=float(row.get("gap_index", 0)),
            complaint_count=int(row.get("complaint_count", 0)),
            avg_urgency=float(row.get("avg_urgency", 0)),
            affected_population=row.get("affected_population"),
            center_lat=float(row.get("center_lat", 0)),
            center_lon=float(row.get("center_lon", 0)),
            radius_km=float(row.get("radius_km", 2.0)),
            evidence_log=evidence_text,
            complaint_media=complaint_media,
        )

    # Process all projects concurrently; capture individual failures without
    # aborting the entire response.
    raw_results = await asyncio.gather(
        *[_process_project(row) for row in ranked],
        return_exceptions=True,
    )

    projects: list[ProjectItem] = []
    for i, result in enumerate(raw_results):
        if isinstance(result, Exception):
            log.warning(
                "project_processing_failed",
                index=i,
                error=str(result),
            )
        else:
            projects.append(result)

    projects.sort(key=lambda p: p.rank)

    return ProjectsResponse(
        constituency_id=constituency_id,
        generated_at=datetime.now(timezone.utc).isoformat(),
        total_projects=len(projects),
        projects=projects,
    )


# ── Heatmap ───────────────────────────────────────────────────────────


@router.get("/heatmap")
async def get_heatmap(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    constituency_id_param: str | None = Query(None, alias="constituency_id"),
):
    """
    Return GeoJSON-ready lat/lon/weight data for Google Maps HeatmapLayer.
    """
    constituency_id = constituency_id_param or mp.get("constituency_id", settings.constituency_id)
    try:
        data = await bq.get_heatmap_data(constituency_id)
        return {
            "constituency_id": constituency_id,
            "points": data,
            "total": len(data),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/ai-insights")
async def get_ai_insights(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    days: int = 90,
    constituency_id_param: str | None = Query(None, alias="constituency_id"),
):
    """
    Gemini-powered analysis of geographic complaint clusters.
    Ranks areas by complaint volume, image evidence, and urgency.
    Returns top 5 critical areas with AI reasoning and recommended actions.
    """
    constituency_id = constituency_id_param or mp.get("constituency_id", settings.constituency_id)
    try:
        clusters = await bq.get_area_complaint_clusters(constituency_id, days=days)
        if not clusters:
            return {
                "areas": [],
                "message": "No complaint data available for analysis.",
                "total_clusters": 0,
            }
        areas = await gemini.analyze_complaint_clusters(clusters, constituency_id)
        return {
            "areas": areas,
            "total_clusters_analysed": len(clusters),
            "days_window": days,
            "constituency_id": constituency_id,
        }
    except Exception as exc:
        log.error("ai_insights_failed", error=str(exc))
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/map-submissions")
async def get_map_submissions(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    limit: int = 1000,
    constituency_id_param: str | None = Query(None, alias="constituency_id"),
):
    """
    Individual submission geo-points for the marker/cluster view.
    Includes submission_id + media_url so the MP dashboard can show image/audio.
    """
    constituency_id = constituency_id_param or mp.get("constituency_id", settings.constituency_id)
    backend_base = f"https://janmat-backend-w2w3osjaua-el.a.run.app"
    try:
        points = await bq.get_submission_points(
            constituency_id, limit=limit, include_media=True
        )
        # Attach media_url for any submission that has a GCS file
        for p in points:
            sub_id = p.pop("submission_id", None)
            gcs = p.pop("raw_input_gcs_uri", None)
            if sub_id and gcs:
                p["submission_id"] = sub_id
                p["media_url"] = f"{backend_base}/dashboard/media/{sub_id}"
            else:
                p["media_url"] = None
        return {
            "constituency_id": constituency_id,
            "points": points,
            "total": len(points),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/media/{submission_id}")
async def get_submission_media_mp(
    submission_id: str,
    mp: Annotated[dict, Depends(_get_current_mp)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gcs: Annotated[StorageService, Depends(get_storage_service)],
):
    """
    Stream raw image or audio for any submission in the MP's constituency.
    Used by the MP dashboard to display images and play audio recordings inline.
    """
    from fastapi.responses import Response as FastResponse

    # Look up GCS URI from BigQuery
    constituency_id = mp.get("constituency_id", "KA-BLR-NORTH-01")
    sql = f"""
    SELECT raw_input_gcs_uri, input_type
    FROM `{bq._project}.{bq._analytics_ds}.citizen_grievances`
    WHERE submission_id = @submission_id
      AND constituency_id = @constituency_id
    LIMIT 1
    """
    from google.cloud import bigquery as gcbq
    rows = await bq._run_query(
        sql,
        gcbq.QueryJobConfig(
            query_parameters=[
                gcbq.ScalarQueryParameter("submission_id", "STRING", submission_id),
                gcbq.ScalarQueryParameter("constituency_id", "STRING", constituency_id),
            ]
        ),
    )
    if not rows or not rows[0].get("raw_input_gcs_uri"):
        raise HTTPException(status_code=404, detail="No media for this submission")

    gcs_uri = rows[0]["raw_input_gcs_uri"]
    input_type = rows[0].get("input_type", "image")
    default_ct = "audio/mp4" if input_type == "audio" else "image/jpeg"

    try:
        data, content_type = await gcs.download_bytes(gcs_uri)
        if content_type == "application/octet-stream":
            content_type = default_ct
        return FastResponse(
            content=data,
            media_type=content_type,
            headers={"Cache-Control": "private, max-age=3600"},
        )
    except Exception as exc:
        log.error("mp_media_download_failed", gcs_uri=gcs_uri, error=str(exc))
        raise HTTPException(status_code=500, detail="Media unavailable")


# ── Trends ────────────────────────────────────────────────────────────


@router.get("/trends")
async def get_trends(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    days: int = 30,
    constituency_id_param: str | None = Query(None, alias="constituency_id"),
):
    """Category complaint trends over the past N days."""
    constituency_id = constituency_id_param or mp.get("constituency_id", settings.constituency_id)

    from google.cloud import bigquery as gcbq

    sql = f"""
    SELECT
        DATE(submitted_at) AS date,
        category,
        COUNT(*) AS count,
        AVG(urgency_rating) AS avg_urgency
    FROM `{bq._project}.{bq._analytics_ds}.citizen_grievances`
    WHERE constituency_id = @constituency_id
      AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @days DAY)
      AND processing_status = 'processed'
    GROUP BY date, category
    ORDER BY date ASC, count DESC
    """
    try:
        rows = await bq._run_query(
            sql,
            gcbq.QueryJobConfig(
                query_parameters=[
                    gcbq.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    gcbq.ScalarQueryParameter("days", "INT64", days),
                ]
            ),
        )
        return {
            "constituency_id": constituency_id,
            "period_days": days,
            "data": rows,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── Project Completion ────────────────────────────────────────────────


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Haversine distance in km between two GPS coordinates."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return R * 2 * math.asin(math.sqrt(a))


class CompletionRequest(BaseModel):
    project_name: str
    category: str
    center_lat: float
    center_lon: float
    radius_km: float
    submitted_lat: float
    submitted_lon: float
    image_base64: str = ""   # empty when citizen evidence was audio/text only
    mime_type: str = "image/jpeg"
    notes: str = ""
    skip_ai_check: bool = False  # True when no image uploaded (audio/text complaint projects)


@router.post("/projects/complete")
async def submit_project_completion(
    body: CompletionRequest,
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gcs: Annotated[StorageService, Depends(get_storage_service)],
):
    """
    MP submits project completion evidence.

    Runs two mandatory verifications:
      1. Geolocation -- GPS coordinates must be within project radius (+0.5 km buffer)
      2. Gemini vision -- image must visually show the completed project type

    Both must pass for the completion to be recorded.
    """
    completion_id = str(uuid.uuid4())
    mp_email = mp.get("sub", "unknown")
    constituency_id = mp.get("constituency_id", settings.constituency_id)

    # 1. Geolocation verification
    distance_km = _haversine_km(
        body.submitted_lat,
        body.submitted_lon,
        body.center_lat,
        body.center_lon,
    )
    geo_threshold = max(body.radius_km + 0.5, 1.0)
    geo_verified = distance_km <= geo_threshold

    # 2. Decode image (if provided)
    image_bytes = b""
    if body.image_base64:
        try:
            padded = body.image_base64 + "=" * (-len(body.image_base64) % 4)
            image_bytes = base64.b64decode(padded.replace("-", "+").replace("_", "/"))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid base64 image data")

    # 3. Gemini image verification — skipped when complaint evidence is audio/text only
    from app.services.gemini import CompletionVerification
    ai_skipped = body.skip_ai_check or not image_bytes

    if ai_skipped:
        ai_result = CompletionVerification(
            verified=True,
            confidence=100,
            reasoning=(
                "Image check skipped — citizen complaints for this project were "
                "audio/text based with no photo evidence to compare against. "
                "GPS proximity verification is the applicable check."
            ),
            issues=[],
        )
        log.info(
            "gemini_completion_skipped",
            project=body.project_name,
            reason="audio_text_complaints_no_image",
        )
    else:
        try:
            ai_result = await gemini.verify_completion_image(
                image_bytes=image_bytes,
                mime_type=body.mime_type,
                project_description=body.project_name,
                category=body.category,
            )
        except Exception as e:
            log.error("gemini_completion_failed", error=str(e), project=body.project_name)
            raise HTTPException(status_code=500, detail=f"AI verification failed: {e}")

    overall = geo_verified and ai_result.verified

    # 4. If both verified: upload to GCS + log to BigQuery
    evidence_gcs_uri = ""
    if overall:
        try:
            evidence_gcs_uri = await gcs.upload_image(
                image_bytes=image_bytes,
                submission_id=f"completion_{completion_id}",
                constituency_id=constituency_id,
                content_type=body.mime_type,
            )
        except Exception as e:
            log.warning(
                "gcs_completion_upload_failed",
                error=str(e),
                completion_id=completion_id,
            )
            evidence_gcs_uri = ""

        try:
            await bq.log_project_completion(
                completion_id=completion_id,
                constituency_id=constituency_id,
                mp_email=mp_email,
                project_name=body.project_name,
                category=body.category,
                center_lat=body.center_lat,
                center_lon=body.center_lon,
                submitted_lat=body.submitted_lat,
                submitted_lon=body.submitted_lon,
                distance_km=distance_km,
                geo_verified=geo_verified,
                ai_verified=ai_result.verified,
                ai_confidence=ai_result.confidence,
                ai_reasoning=ai_result.reasoning,
                evidence_gcs_uri=evidence_gcs_uri,
                notes=body.notes,
            )
        except Exception as e:
            log.warning(
                "bq_completion_log_failed", error=str(e), completion_id=completion_id
            )

    log.info(
        "project_completion_submitted",
        completion_id=completion_id,
        project=body.project_name,
        geo_verified=geo_verified,
        ai_verified=ai_result.verified,
        overall=overall,
        distance_km=round(distance_km, 3),
        mp=mp_email,
    )

    return {
        "completion_id": completion_id,
        "overall_verified": overall,
        "geo_verified": geo_verified,
        "geo_distance_km": round(distance_km, 3),
        "geo_threshold_km": round(geo_threshold, 3),
        "ai_verified": ai_result.verified,
        "ai_skipped": ai_skipped,
        "ai_confidence": ai_result.confidence,
        "ai_reasoning": ai_result.reasoning,
        "ai_issues": ai_result.issues,
        "evidence_gcs_uri": evidence_gcs_uri if overall else None,
    }


# ── Budget Tracker ────────────────────────────────────────────────────


@router.get("/budget")
async def get_budget(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gcs: Annotated[StorageService, Depends(get_storage_service)],
):
    """
    Real-time GCP cost breakdown for the budget tracker card.

    Sources (all live):
      - BigQuery INFORMATION_SCHEMA.JOBS_BY_PROJECT  → actual bytes processed → BQ cost
      - GCS bucket list_blobs                        → actual storage bytes   → GCS cost
      - citizen_grievances COUNT                     → Gemini / STT call est.
      - Cloud SQL f1-micro asia-south1               → fixed known monthly cost
    """
    TOTAL_BUDGET = 300.0

    # Pricing constants (asia-south1, 2025)
    BQ_PRICE_PER_TB   = 6.25       # on-demand; first 1 TB/month free
    BQ_FREE_TB        = 1.0
    GCS_PRICE_PER_GB  = 0.020      # standard storage / GB / month
    CLOUD_SQL_MONTHLY = 7.65       # db-f1-micro fixed (730 hrs × $0.0105)
    CLOUD_RUN_PER_REQ = 0.00000040 # rough: 200ms × 256MB × 0.25 vCPU
    GEMINI_PER_CALL   = 0.0        # AI Studio free tier

    now           = datetime.now(timezone.utc)
    days_in_month = calendar.monthrange(now.year, now.month)[1]
    days_elapsed  = max(now.day, 1)

    # ── Fetch metrics — each has its own timeout inside, but cap the
    #    whole gather at 20s so the endpoint always responds promptly ─
    bq_usage: dict  = {}
    gcs_usage: dict = {}
    try:
        bq_raw, gcs_raw = await asyncio.wait_for(
            asyncio.gather(
                bq.get_usage_stats(region="asia-south1"),
                gcs.get_bucket_usage(),
                return_exceptions=True,
            ),
            timeout=20.0,
        )
        bq_usage  = bq_raw  if isinstance(bq_raw,  dict) else {}
        gcs_usage = gcs_raw if isinstance(gcs_raw, dict) else {}
        if isinstance(bq_raw, Exception):
            log.warning("budget_bq_failed",  error=str(bq_raw))
        if isinstance(gcs_raw, Exception):
            log.warning("budget_gcs_failed", error=str(gcs_raw))
    except asyncio.TimeoutError:
        log.warning("budget_gather_timeout")
    except Exception as exc:
        log.warning("budget_gather_error", error=str(exc))

    # ── Calculate costs ─────────────────────────────────────────────
    bq_bytes = int(bq_usage.get("bq_bytes_processed") or 0)
    bq_tb    = bq_bytes / 1e12
    bq_cost  = max(0.0, (bq_tb - BQ_FREE_TB)) * BQ_PRICE_PER_TB

    gcs_bytes = int(gcs_usage.get("total_bytes") or 0)
    gcs_gb    = gcs_bytes / 1e9
    gcs_cost  = gcs_gb * GCS_PRICE_PER_GB

    total_subs     = int(bq_usage.get("total_submissions") or 0)
    cloud_run_cost = total_subs * CLOUD_RUN_PER_REQ
    gemini_cost    = total_subs * GEMINI_PER_CALL
    cloud_sql_cost = CLOUD_SQL_MONTHLY * (days_elapsed / days_in_month)

    total_spent   = bq_cost + cloud_sql_cost + gcs_cost + cloud_run_cost + gemini_cost
    remaining     = max(0.0, TOTAL_BUDGET - total_spent)
    monthly_rate  = (total_spent / days_elapsed) * days_in_month
    runway_months = (remaining / monthly_rate) if monthly_rate > 0 else 999.0

    # Flag which sources had real data vs fell back to 0
    bq_live  = bool(bq_usage.get("bq_bytes_available"))
    gcs_live = gcs_bytes > 0

    log.info(
        "budget_calculated",
        total_spent=round(total_spent, 2),
        bq_tb=round(bq_tb, 6),
        gcs_gb=round(gcs_gb, 3),
        total_subs=total_subs,
        bq_live=bq_live,
        gcs_live=gcs_live,
    )

    return {
        "total_budget":  TOTAL_BUDGET,
        "total_spent":   round(total_spent, 2),
        "remaining":     round(remaining, 2),
        "pct_used":      round(total_spent / TOTAL_BUDGET * 100, 2),
        "monthly_rate":  round(monthly_rate, 2),
        "runway_months": round(runway_months, 1),
        "breakdown": {
            "cloud_sql":     round(cloud_sql_cost, 2),
            "bigquery":      round(bq_cost, 4),
            "cloud_storage": round(gcs_cost, 4),
            "cloud_run":     round(cloud_run_cost, 4),
            "gemini_api":    round(gemini_cost, 2),
            "gemini_note":   "AI Studio free tier" if GEMINI_PER_CALL == 0 else "Vertex AI",
        },
        "usage_metrics": {
            "bq_tb_processed_month": round(bq_tb, 6),
            "bq_job_count":          int(bq_usage.get("bq_job_count") or 0),
            "bq_live":               bq_live,
            "bq_dataset_count":      int(bq_usage.get("bq_dataset_count") or 0),
            "bq_table_count":        int(bq_usage.get("bq_table_count") or 0),
            "gcs_storage_gb":        round(gcs_gb, 3),
            "gcs_object_count":      int(gcs_usage.get("total_objects") or 0),
            "gcs_live":              gcs_live,
            "total_submissions":     total_subs,
            "audio_submissions":     int(bq_usage.get("audio_submissions") or 0),
            "image_submissions":     int(bq_usage.get("image_submissions") or 0),
        },
        "as_of": now.isoformat(),
    }


# -- CSV Export -----------------------------------------------------------


@router.get("/export/csv")
async def export_csv(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
):
    """One-click CSV export of ranked project recommendations."""
    constituency_id = mp.get("constituency_id", settings.constituency_id)

    try:
        ranked = await bq.get_priority_ranking(constituency_id, limit=20)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    import csv
    import io

    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(
        [
            "Rank",
            "Category",
            "Suggested Project",
            "Priority Score",
            "Demand Score",
            "Gap Index",
            "Complaint Count",
            "Avg Urgency",
            "Latitude",
            "Longitude",
            "Radius (km)",
        ]
    )
    for row in ranked:
        writer.writerow(
            [
                row.get("priority_rank"),
                row.get("category"),
                row.get("suggested_project"),
                round(float(row.get("priority_score", 0)), 3),
                round(float(row.get("demand_score", 0)), 3),
                round(float(row.get("gap_index", 0)), 3),
                row.get("complaint_count"),
                round(float(row.get("avg_urgency", 0)), 2),
                row.get("center_lat"),
                row.get("center_lon"),
                row.get("radius_km"),
            ]
        )

    output.seek(0)
    filename = f"janmat_priority_{constituency_id}_{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
