"""
Phase 2 — Analytics Router (internal / admin-triggered)

These endpoints trigger the BigQuery analytical pipeline.
In production, they are triggered by Pub/Sub push subscriptions,
not called directly by citizens.

Endpoints:
  POST /analytics/cluster          — run spatial demand clustering
  POST /analytics/score            — compute priority scores from hotspots
  POST /analytics/evidence         — generate Gemini Evidence Logs
  POST /analytics/pubsub/callback  — Pub/Sub push subscription handler
  GET  /analytics/stats            — submission stats for a constituency
"""

import base64
import json
from datetime import datetime, timezone
from typing import Annotated

import structlog
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from pydantic import BaseModel

from app.config import Settings, get_settings
from app.services.bigquery import BigQueryService, get_bigquery_service
from app.services.gemini import GeminiService, get_gemini_service
from app.services.pubsub import PubSubService, get_pubsub_service

log = structlog.get_logger()
router = APIRouter(prefix="/analytics", tags=["analytics"])


# ── Clustering ────────────────────────────────────────────────────────


class ClusterRequest(BaseModel):
    constituency_id: str | None = None


class ClusterResponse(BaseModel):
    constituency_id: str
    hotspots_created: int
    run_at: str


@router.post("/cluster", response_model=ClusterResponse)
async def run_clustering(
    request: ClusterRequest,
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
):
    """
    Trigger BigQuery spatial clustering to aggregate grievances into demand hotspots.
    Idempotent — re-running replaces existing hotspots with fresh data.
    """
    constituency_id = request.constituency_id or settings.constituency_id

    try:
        # Truncate stale rows so each run produces a clean slate
        await bq.truncate_pipeline_data(constituency_id)
        hotspots = await bq.run_demand_clustering(constituency_id)
        if hotspots:
            await bq.insert_hotspots(hotspots)
        return ClusterResponse(
            constituency_id=constituency_id,
            hotspots_created=len(hotspots),
            run_at=datetime.now(timezone.utc).isoformat(),
        )
    except Exception as exc:
        log.error("clustering_failed", constituency_id=constituency_id, error=str(exc))
        raise HTTPException(status_code=500, detail=str(exc))


# ── Priority Scoring ──────────────────────────────────────────────────


class ScoringResponse(BaseModel):
    constituency_id: str
    ranked_projects: int
    run_at: str


@router.post("/score", response_model=ScoringResponse)
async def run_scoring(
    request: ClusterRequest,
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    pubsub: Annotated[PubSubService, Depends(get_pubsub_service)],
    background_tasks: BackgroundTasks,
):
    """
    Compute Priority Scores (P = 0.6×D + 0.4×G) from demand hotspots.
    Must run after /cluster.
    """
    constituency_id = request.constituency_id or settings.constituency_id

    try:
        ranked = await bq.run_priority_scoring(constituency_id)
        if ranked:
            await bq.insert_priority_scores(ranked)
            # Notify MP dashboard
            background_tasks.add_task(
                pubsub.publish_priority_updated,
                constituency_id,
                ranked[0].get("priority_rank", 1),
            )
        return ScoringResponse(
            constituency_id=constituency_id,
            ranked_projects=len(ranked),
            run_at=datetime.now(timezone.utc).isoformat(),
        )
    except Exception as exc:
        log.error("scoring_failed", constituency_id=constituency_id, error=str(exc))
        raise HTTPException(status_code=500, detail=str(exc))


# ── Evidence Log Generation ───────────────────────────────────────────


class EvidenceResponse(BaseModel):
    constituency_id: str
    evidence_logs_generated: int
    run_at: str


@router.post("/evidence", response_model=EvidenceResponse)
async def generate_evidence(
    request: ClusterRequest,
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
):
    """
    Generate Gemini Evidence Logs for each ranked project.
    Must run after /score.
    """
    constituency_id = request.constituency_id or settings.constituency_id

    try:
        ranked = await bq.get_priority_ranking(constituency_id, limit=10)
        if not ranked:
            return EvidenceResponse(
                constituency_id=constituency_id,
                evidence_logs_generated=0,
                run_at=datetime.now(timezone.utc).isoformat(),
            )

        count = 0
        for project in ranked:
            category = project.get("category", "")
            infra_facts = await bq.get_infrastructure_facts(constituency_id, category)
            evidence_text = await gemini.generate_evidence_log(
                hotspot=project,
                infra_facts=infra_facts.get("summary", "No data available"),
            )
            # Store evidence back — update BigQuery row
            # (In production, would UPDATE demand_hotspots.evidence_log)
            # For POC: log it; Cloud SQL evidence_cache stores it
            log.info(
                "evidence_generated",
                rank=project.get("priority_rank"),
                category=category,
                chars=len(evidence_text),
            )
            count += 1

        return EvidenceResponse(
            constituency_id=constituency_id,
            evidence_logs_generated=count,
            run_at=datetime.now(timezone.utc).isoformat(),
        )
    except Exception as exc:
        log.error(
            "evidence_generation_failed",
            constituency_id=constituency_id,
            error=str(exc),
        )
        raise HTTPException(status_code=500, detail=str(exc))


# ── Pub/Sub Push Handler ──────────────────────────────────────────────


@router.post("/pubsub/callback", status_code=status.HTTP_204_NO_CONTENT)
async def pubsub_push_handler(
    raw_request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
    pubsub: Annotated[PubSubService, Depends(get_pubsub_service)],
    background_tasks: BackgroundTasks,
):
    """
    Pub/Sub push subscription handler.
    Receives notifications from 'grievance-submitted' topic.
    Triggers clustering + scoring pipeline asynchronously.
    """
    try:
        body = await raw_request.json()
        message = body.get("message", {})
        data_b64 = message.get("data", "")
        payload = json.loads(base64.b64decode(data_b64).decode("utf-8"))
    except Exception as exc:
        log.error("pubsub_parse_failed", error=str(exc))
        # Return 204 to ACK and avoid redelivery of malformed messages
        return

    constituency_id = payload.get("constituency_id", settings.constituency_id)
    submission_id = payload.get("submission_id")

    log.info(
        "pubsub_callback_received",
        submission_id=submission_id,
        constituency_id=constituency_id,
    )

    # Fire-and-forget: run clustering + scoring in background
    async def _run_pipeline():
        try:
            await bq.truncate_pipeline_data(constituency_id)
            hotspots = await bq.run_demand_clustering(constituency_id)
            if hotspots:
                await bq.insert_hotspots(hotspots)
            ranked = await bq.run_priority_scoring(constituency_id)
            if ranked:
                await bq.insert_priority_scores(ranked)
                await pubsub.publish_priority_updated(constituency_id)
        except Exception as e:
            log.error("pipeline_failed", constituency_id=constituency_id, error=str(e))

    background_tasks.add_task(_run_pipeline)


# ── Stats ─────────────────────────────────────────────────────────────


@router.get("/stats/{constituency_id}")
async def get_stats(
    constituency_id: str,
    bq: Annotated[BigQueryService, Depends(get_bigquery_service)],
):
    """Submission volume stats for admin/monitoring."""
    try:
        heatmap = await bq.get_heatmap_data(constituency_id)
        category_counts: dict[str, int] = {}
        for row in heatmap:
            cat = row.get("category", "Other")
            category_counts[cat] = category_counts.get(cat, 0) + int(
                row.get("weight", 0)
            )

        return {
            "constituency_id": constituency_id,
            "total_hotspots": len(heatmap),
            "total_complaints": sum(category_counts.values()),
            "by_category": category_counts,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
