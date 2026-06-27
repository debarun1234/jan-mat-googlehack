"""
Phase 3 — MP Executive Dashboard Router

Endpoints:
  POST /dashboard/auth/login       — JWT login for MP
  GET  /dashboard/projects         — ranked project list with evidence
  GET  /dashboard/heatmap          — lat/lon data for Google Maps overlay
  GET  /dashboard/trends           — category trends over time
  GET  /dashboard/export/csv       — CSV export of ranked recommendations
"""
from datetime import datetime, timedelta, timezone
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel

from app.config import Settings, get_settings
from app.services.bigquery import BigQueryService, get_bigquery_service
from app.services.gemini import GeminiService, get_gemini_service

log = structlog.get_logger()
router = APIRouter(prefix="/dashboard", tags=["dashboard"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/dashboard/auth/login")

# ── Demo MP credentials (replace with Cloud SQL lookup in production) ──
DEMO_MP = {
    "username": "mp@janmat.demo",
    "password": "JanMat@2025!",  # Override via Secret Manager in prod
    "name": "Demo MP",
    "constituency_id": "KA-BLR-NORTH-01",
}


# ── Auth ──────────────────────────────────────────────────────────────

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    mp_name: str
    constituency_id: str


def _create_jwt(data: dict, settings: Settings) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {**data, "exp": expire, "iat": datetime.now(timezone.utc)}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


async def _get_current_mp(
    token: Annotated[str, Depends(oauth2_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
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


@router.post("/auth/login", response_model=TokenResponse)
async def login(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """JWT login for MP. Returns bearer token."""
    if (
        form_data.username != DEMO_MP["username"]
        or form_data.password != DEMO_MP["password"]
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    token = _create_jwt(
        {
            "sub": DEMO_MP["username"],
            "name": DEMO_MP["name"],
            "constituency_id": DEMO_MP["constituency_id"],
        },
        settings,
    )
    log.info("mp_login", username=form_data.username)
    return TokenResponse(
        access_token=token,
        expires_in=settings.jwt_expire_minutes * 60,
        mp_name=DEMO_MP["name"],
        constituency_id=DEMO_MP["constituency_id"],
    )


# ── Projects ─────────────────────────────────────────────────────────

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
):
    """
    Return ranked development projects with Gemini Evidence Logs.

    This is the core Phase 3 output — what the MP sees.
    """
    constituency_id = mp.get("constituency_id", settings.constituency_id)

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

    projects = []
    for row in ranked:
        evidence_text = None
        if generate_evidence:
            try:
                infra = await bq.get_infrastructure_facts(
                    constituency_id,
                    row.get("category", ""),
                )
                evidence_text = await gemini.generate_evidence_log(
                    hotspot=row,
                    infra_facts=infra.get("summary", ""),
                )
            except Exception as e:
                log.warning("evidence_log_failed", rank=row.get("priority_rank"), error=str(e))
                evidence_text = f"Evidence generation unavailable: {str(e)}"

        projects.append(
            ProjectItem(
                rank=int(row.get("priority_rank", 0)),
                category=row.get("category", ""),
                suggested_project=row.get("suggested_project", ""),
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
            )
        )

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
):
    """
    Return GeoJSON-ready lat/lon/weight data for Google Maps HeatmapLayer.
    """
    constituency_id = mp.get("constituency_id", settings.constituency_id)
    try:
        data = await bq.get_heatmap_data(constituency_id)
        return {
            "constituency_id": constituency_id,
            "points": data,
            "total": len(data),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── Trends ────────────────────────────────────────────────────────────

@router.get("/trends")
async def get_trends(
    mp: Annotated[dict, Depends(_get_current_mp)],
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    days: int = 30,
):
    """Category complaint trends over the past N days."""
    constituency_id = mp.get("constituency_id", settings.constituency_id)
    client = bq._get_client()

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
        job = client.query(
            sql,
            job_config=gcbq.QueryJobConfig(
                query_parameters=[
                    gcbq.ScalarQueryParameter("constituency_id", "STRING", constituency_id),
                    gcbq.ScalarQueryParameter("days", "INT64", days),
                ]
            ),
        )
        rows = [dict(r) for r in job.result()]
        return {
            "constituency_id": constituency_id,
            "period_days": days,
            "data": rows,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── CSV Export ────────────────────────────────────────────────────────

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

    writer.writerow([
        "Rank", "Category", "Suggested Project",
        "Priority Score", "Demand Score", "Gap Index",
        "Complaint Count", "Avg Urgency",
        "Latitude", "Longitude", "Radius (km)",
    ])
    for row in ranked:
        writer.writerow([
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
        ])

    output.seek(0)
    filename = f"janmat_priority_{constituency_id}_{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
