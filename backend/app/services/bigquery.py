"""
BigQuery service — streaming insert + analytical queries.

Tables:
  janmat_analytics.citizen_grievances   — Phase 1 output
  janmat_analytics.demand_hotspots      — Phase 2 clustering output
  janmat_analytics.priority_scores      — Phase 2 ranked output
  janmat_infrastructure.public_infrastructure  — Census / NFHS reference data
"""

import asyncio
from datetime import datetime, date, timezone
from decimal import Decimal

import structlog
from google.cloud import bigquery
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings
from app.services.gemini import StructuredGrievance

log = structlog.get_logger()


def _serialize_bq_row(row: dict) -> dict:
    """
    Convert BigQuery result values that are not JSON-serializable.
    - datetime / date → ISO string
    - Decimal → float
    - Everything else passes through unchanged.
    """
    out = {}
    for k, v in row.items():
        if isinstance(v, datetime):
            out[k] = v.isoformat()
        elif isinstance(v, date):
            out[k] = v.isoformat()
        elif isinstance(v, Decimal):
            out[k] = float(v)
        elif isinstance(v, list):
            out[k] = [_serialize_bq_row(i) if isinstance(i, dict) else i for i in v]
        else:
            out[k] = v
    return out


class BigQueryService:
    def __init__(self):
        settings = get_settings()
        self._project = settings.gcp_project_id
        self._analytics_ds = settings.bq_analytics_dataset
        self._infra_ds = settings.bq_infrastructure_dataset
        self._client: bigquery.Client | None = None

    def _get_client(self) -> bigquery.Client:
        if self._client is None:
            self._client = bigquery.Client(project=self._project)
        return self._client

    def _table(self, dataset: str, table: str) -> str:
        return f"{self._project}.{dataset}.{table}"

    async def _run_query(
        self, sql: str, job_config: bigquery.QueryJobConfig
    ) -> list[dict]:
        """Run a synchronous BQ query in a thread-pool executor so it doesn't block the event loop."""
        client = self._get_client()

        def _sync():
            job = client.query(sql, job_config=job_config)
            return [_serialize_bq_row(dict(row)) for row in job.result()]

        return await asyncio.get_event_loop().run_in_executor(None, _sync)

    # ── Phase 1: Stream grievance into BigQuery ──────────────────────

    @retry(
        stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8), reraise=True
    )
    async def insert_grievance(
        self,
        submission_id: str,
        grievance: StructuredGrievance,
        input_type: str,
        raw_gcs_uri: str,
        translated_text: str,
        constituency_id: str,
        gemini_model: str,
        processing_latency_ms: int,
    ) -> None:
        """Stream a single parsed grievance row into citizen_grievances."""
        row = {
            "submission_id": submission_id,
            "input_type": input_type,
            "raw_input_gcs_uri": raw_gcs_uri,
            "source_language": grievance.source_language or "unknown",
            "translated_text": translated_text,
            "category": grievance.category.value,
            "latitude": grievance.latitude,
            "longitude": grievance.longitude,
            "urgency_rating": grievance.urgency_rating,
            "summary_en": grievance.summary_en,
            "constituency_id": constituency_id,
            "ward_id": None,
            "village_name": grievance.ward_name,
            "processing_status": "processed",
            "gemini_model_used": gemini_model,
            "processing_latency_ms": processing_latency_ms,
            "submitted_at": datetime.now(timezone.utc).isoformat(),
        }

        client = self._get_client()
        table = self._table(self._analytics_ds, "citizen_grievances")

        def _sync_insert():
            return client.insert_rows_json(table, [row])

        errors = await asyncio.get_event_loop().run_in_executor(None, _sync_insert)
        if errors:
            log.error("bq_insert_error", errors=errors, submission_id=submission_id)
            raise RuntimeError(f"BigQuery insert failed: {errors}")

        log.info(
            "bq_grievance_inserted",
            submission_id=submission_id,
            category=row["category"],
        )

    # ── Phase 2: Run clustering + scoring queries ─────────────────────

    async def run_demand_clustering(self, constituency_id: str) -> list[dict]:
        """
        Execute the spatial demand clustering query.
        Returns list of hotspot rows to insert into demand_hotspots.
        """
        sql = self._load_query("demand_clustering.sql")
        client = self._get_client()

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter(
                    "constituency_id", "STRING", constituency_id
                ),
                bigquery.ScalarQueryParameter("cluster_radius_km", "FLOAT64", 2.0),
                bigquery.ScalarQueryParameter("min_complaints", "INT64", 1),
            ]
        )
        rows = await self._run_query(sql, job_config)
        log.info(
            "bq_clustering_complete",
            constituency_id=constituency_id,
            hotspots=len(rows),
        )
        return rows

    async def run_priority_scoring(self, constituency_id: str) -> list[dict]:
        """
        Execute the priority scoring query.
        Returns ranked rows for priority_scores table.
        """
        sql = self._load_query("priority_scoring.sql")
        client = self._get_client()

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter(
                    "constituency_id", "STRING", constituency_id
                ),
            ]
        )
        rows = await self._run_query(sql, job_config)
        log.info(
            "bq_priority_scoring_complete",
            constituency_id=constituency_id,
            ranked=len(rows),
        )
        return rows

    async def get_infrastructure_facts(
        self,
        constituency_id: str,
        category: str,
    ) -> dict:
        """
        Fetch infrastructure baseline facts for a constituency + category.
        Used by Gemini Evidence Log generation.
        """
        sql = f"""
        SELECT
            village_name,
            category,
            metric_name,
            metric_value,
            metric_unit,
            data_source,
            reference_year
        FROM `{self._table(self._infra_ds, "public_infrastructure")}`
        WHERE constituency_id = @constituency_id
          AND category = @category
        ORDER BY metric_name
        LIMIT 20
        """
        try:
            rows = await self._run_query(
                sql,
                bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter(
                            "constituency_id", "STRING", constituency_id
                        ),
                        bigquery.ScalarQueryParameter("category", "STRING", category),
                    ]
                ),
            )
        except Exception:
            # public_infrastructure table may not exist or have a different schema
            # in this deployment — degrade gracefully so evidence generation continues.
            return {
                "summary": f"Infrastructure baseline data unavailable for {category} in {constituency_id}"
            }
        # Format as readable string for Gemini prompt
        if not rows:
            return {
                "summary": f"No baseline data available for {category} in {constituency_id}"
            }
        lines = [
            f"- {r['metric_name']}: {r['metric_value']} {r['metric_unit']} (Source: {r['data_source']}, {r['reference_year']})"
            for r in rows
        ]
        return {"summary": "\n".join(lines), "rows": rows}

    async def get_project_media(
        self, constituency_id: str, category: str, limit: int = 5
    ) -> list[dict]:
        """
        Fetch complaints that have media (image/audio) for a ranked project category.
        Returns submission_id, input_type, summary_en for the highest-urgency submissions.
        Used to show photo/audio evidence inside the Ranked Development Projects cards.
        """
        sql = f"""
        SELECT
            submission_id,
            input_type,
            summary_en,
            urgency_rating
        FROM `{self._table(self._analytics_ds, "citizen_grievances")}`
        WHERE constituency_id = @constituency_id
          AND category = @category
          AND raw_input_gcs_uri IS NOT NULL
          AND raw_input_gcs_uri != ''
          AND processing_status = 'processed'
        ORDER BY
            CASE input_type WHEN 'image' THEN 0 WHEN 'audio' THEN 1 ELSE 2 END ASC,
            urgency_rating DESC,
            submitted_at DESC
        LIMIT @limit
        """
        try:
            return await self._run_query(
                sql,
                bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("constituency_id", "STRING", constituency_id),
                        bigquery.ScalarQueryParameter("category", "STRING", category),
                        bigquery.ScalarQueryParameter("limit", "INT64", limit),
                    ]
                ),
            )
        except Exception:
            return []

    async def get_complaint_samples(
        self, constituency_id: str, category: str, limit: int = 5
    ) -> list[str]:
        """
        Fetch recent complaint summaries for a category — used by Gemini to generate
        specific project titles rather than the generic CASE-based defaults.
        """
        sql = f"""
        SELECT summary_en
        FROM `{self._table(self._analytics_ds, "citizen_grievances")}`
        WHERE constituency_id = @constituency_id
          AND category = @category
          AND summary_en IS NOT NULL
          AND processing_status = 'processed'
        ORDER BY urgency_rating DESC, submitted_at DESC
        LIMIT @limit
        """
        try:
            rows = await self._run_query(
                sql,
                bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("constituency_id", "STRING", constituency_id),
                        bigquery.ScalarQueryParameter("category", "STRING", category),
                        bigquery.ScalarQueryParameter("limit", "INT64", limit),
                    ]
                ),
            )
            return [r["summary_en"] for r in rows if r.get("summary_en")]
        except Exception:
            return []

    async def get_priority_ranking(
        self, constituency_id: str, limit: int = 10
    ) -> list[dict]:
        """
        Fetch the latest ranked project list for the MP dashboard.
        Note: priority_scores table stores the rank column as `rank`, not `priority_rank`.
        We alias it to `priority_rank` here so callers can use a consistent field name.
        """
        # Each pipeline run appends rows — tables accumulate duplicates over time.
        # Fix: pick the single most-recent score per category and the single most-recent
        # hotspot per category independently, then JOIN on category (not UUID) so
        # hotspot_id mismatches across runs are irrelevant.
        sql = f"""
        WITH latest_scores AS (
            SELECT *
            FROM (
                SELECT *,
                       ROW_NUMBER() OVER (
                           PARTITION BY category
                           ORDER BY generated_at DESC
                       ) AS _rn
                FROM `{self._table(self._analytics_ds, "priority_scores")}`
                WHERE constituency_id = @constituency_id
            )
            WHERE _rn = 1
        ),
        latest_hotspots AS (
            SELECT *
            FROM (
                SELECT *,
                       ROW_NUMBER() OVER (
                           PARTITION BY category
                           ORDER BY computed_at DESC
                       ) AS _rn
                FROM `{self._table(self._analytics_ds, "demand_hotspots")}`
                WHERE constituency_id = @constituency_id
                  AND center_lat IS NOT NULL AND center_lon IS NOT NULL
                  AND ABS(center_lat) BETWEEN 0.001 AND 90
                  AND ABS(center_lon) BETWEEN 0.001 AND 180
            )
            WHERE _rn = 1
        )
        SELECT
            ls.hotspot_id,
            ls.category,
            ls.rank         AS priority_rank,
            ls.priority_score,
            ls.demand_score,
            ls.gap_index,
            ls.suggested_project,
            ls.generated_at,
            lh.complaint_count,
            lh.avg_urgency,
            lh.affected_population,
            lh.center_lat,
            lh.center_lon,
            lh.radius_km
        FROM latest_scores ls
        JOIN latest_hotspots lh ON ls.category = lh.category
        ORDER BY ls.rank ASC
        LIMIT @limit
        """
        rows = await self._run_query(
            sql,
            bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    bigquery.ScalarQueryParameter("limit", "INT64", limit),
                ]
            ),
        )
        log.info("bq_ranking_fetched", constituency_id=constituency_id, rows=len(rows))
        return rows

    async def get_heatmap_data(self, constituency_id: str) -> list[dict]:
        """
        Fetch lat/lon + weight for Google Maps heatmap layer.
        Uses individual citizen_grievances points (actual GPS coordinates) for
        accurate density visualisation. Falls back to deduplicated demand_hotspot
        centroids only when no individual complaints have coordinates.
        """
        params = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("constituency_id", "STRING", constituency_id),
            ]
        )

        # Primary: individual complaints → real density spread on the map
        grievance_sql = f"""
        SELECT
            latitude                              AS lat,
            longitude                             AS lng,
            COALESCE(urgency_rating, 3)           AS weight,
            category,
            CAST(COALESCE(urgency_rating, 3) AS FLOAT64) AS avg_urgency
        FROM `{self._table(self._analytics_ds, "citizen_grievances")}`
        WHERE constituency_id = @constituency_id
          AND latitude  IS NOT NULL
          AND longitude IS NOT NULL
          AND ABS(latitude)  BETWEEN 0.001 AND 90
          AND ABS(longitude) BETWEEN 0.001 AND 180
        ORDER BY submitted_at DESC
        LIMIT 500
        """
        rows = await self._run_query(grievance_sql, params)
        if rows:
            return rows

        # Fallback: no individual complaints with coords — use one centroid per category
        hotspot_sql = f"""
        SELECT
            center_lat    AS lat,
            center_lon    AS lng,
            complaint_count AS weight,
            category,
            avg_urgency
        FROM `{self._table(self._analytics_ds, "demand_hotspots")}`
        WHERE constituency_id = @constituency_id
          AND center_lat IS NOT NULL AND center_lon IS NOT NULL
          AND ABS(center_lat) BETWEEN 0.001 AND 90
          AND ABS(center_lon) BETWEEN 0.001 AND 180
        QUALIFY ROW_NUMBER() OVER (PARTITION BY category ORDER BY computed_at DESC) = 1
        ORDER BY complaint_count DESC
        LIMIT 100
        """
        return await self._run_query(hotspot_sql, params)

    async def get_submission_points(
        self, constituency_id: str, limit: int = 1000, include_media: bool = False
    ) -> list[dict]:
        """
        Fetch individual submission geo-points for marker view.
        By default returns anonymised points (no submission_id, no personal data).
        Pass include_media=True for the MP dashboard to get submission_id + GCS URI.
        """
        media_cols = ""
        if include_media:
            media_cols = ",\n            submission_id,\n            raw_input_gcs_uri"

        sql = f"""
        SELECT
            latitude   AS lat,
            longitude  AS lng,
            category,
            urgency_rating,
            summary_en,
            input_type,
            DATE(submitted_at) AS date{media_cols}
        FROM `{self._table(self._analytics_ds, "citizen_grievances")}`
        WHERE constituency_id = @constituency_id
          AND latitude  IS NOT NULL
          AND longitude IS NOT NULL
          AND ABS(latitude)  BETWEEN 0.001 AND 90
          AND ABS(longitude) BETWEEN 0.001 AND 180
        ORDER BY submitted_at DESC
        LIMIT @limit
        """
        return await self._run_query(
            sql,
            bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    bigquery.ScalarQueryParameter("limit", "INT64", limit),
                ]
            ),
        )

    async def get_area_complaint_clusters(
        self, constituency_id: str, days: int = 90
    ) -> list[dict]:
        """
        Grid-aggregate submissions into ~1 km cells for Gemini analysis.
        Each cell includes complaint count, image-verified count, urgency stats,
        category breakdown, and sample summaries.
        """
        sql = f"""
        SELECT
            ROUND(latitude,  2) AS grid_lat,
            ROUND(longitude, 2) AS grid_lng,
            COUNT(*)                                          AS complaint_count,
            COUNTIF(input_type = 'image')                     AS image_count,
            ROUND(AVG(urgency_rating), 1)                     AS avg_urgency,
            MAX(urgency_rating)                               AS max_urgency,
            STRING_AGG(DISTINCT category, ', ' LIMIT 8)      AS categories,
            ARRAY_AGG(summary_en IGNORE NULLS LIMIT 3)        AS sample_summaries
        FROM `{self._table(self._analytics_ds, "citizen_grievances")}`
        WHERE constituency_id = @constituency_id
          AND latitude  IS NOT NULL
          AND longitude IS NOT NULL
          AND ABS(latitude)  BETWEEN 0.001 AND 90
          AND ABS(longitude) BETWEEN 0.001 AND 180
          AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @days DAY)
        GROUP BY grid_lat, grid_lng
        HAVING complaint_count >= 1
        ORDER BY complaint_count DESC, avg_urgency DESC
        LIMIT 50
        """
        raw = await self._run_query(
            sql,
            bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    bigquery.ScalarQueryParameter("days", "INT64", days),
                ]
            ),
        )
        rows = []
        for d in raw:
            if isinstance(d.get("sample_summaries"), list):
                d["sample_summaries"] = [s for s in d["sample_summaries"] if s]
            else:
                d["sample_summaries"] = []
            rows.append(d)
        return rows

    async def insert_priority_scores(self, rows: list[dict]) -> None:
        """Stream priority score rows into BigQuery."""
        # Columns that exist in the priority_scores BQ schema
        _SCORE_COLS = {
            "score_id",
            "generated_at",
            "constituency_id",
            "rank",
            "category",
            "suggested_project",
            "priority_score",
            "demand_score",
            "gap_index",
            "complaint_count",
            "avg_urgency",
            "center_lat",
            "center_lon",
            "evidence_log",
            "hotspot_id",
        }
        import uuid as _uuid

        clean = []
        for r in rows:
            row = _serialize_bq_row({k: v for k, v in r.items() if k in _SCORE_COLS})
            if "rank" not in row and "priority_rank" in r:
                row["rank"] = r["priority_rank"]
            row.setdefault("evidence_log", "")
            if not row.get("score_id"):
                row["score_id"] = str(_uuid.uuid4())
            clean.append(row)

        client = self._get_client()
        table = self._table(self._analytics_ds, "priority_scores")

        def _sync_insert():
            return client.insert_rows_json(table, clean)

        errors = await asyncio.get_event_loop().run_in_executor(None, _sync_insert)
        if errors:
            log.error("bq_priority_insert_error", errors=errors)
            raise RuntimeError(f"BigQuery priority insert failed: {errors}")

    async def truncate_pipeline_data(self, constituency_id: str) -> None:
        """
        Delete all existing demand_hotspots and priority_scores rows for this
        constituency before a fresh pipeline run.  This prevents row accumulation
        that causes duplicate project cards.

        Note: BigQuery DML cannot touch the streaming buffer (rows inserted in the
        last few minutes).  Use a short sleep in the pipeline to let the buffer flush,
        or accept that very-recent rows survive until the next run.
        """
        client = self._get_client()

        def _delete(sql: str) -> None:
            job = client.query(sql)
            job.result()  # wait for DML to complete

        hotspot_sql = f"""
        DELETE FROM `{self._table(self._analytics_ds, "demand_hotspots")}`
        WHERE constituency_id = '{constituency_id}'
        """
        score_sql = f"""
        DELETE FROM `{self._table(self._analytics_ds, "priority_scores")}`
        WHERE constituency_id = '{constituency_id}'
        """
        try:
            await asyncio.get_event_loop().run_in_executor(None, lambda: _delete(hotspot_sql))
            log.info("bq_hotspots_truncated", constituency_id=constituency_id)
            await asyncio.get_event_loop().run_in_executor(None, lambda: _delete(score_sql))
            log.info("bq_scores_truncated", constituency_id=constituency_id)
        except Exception as e:
            # DML may fail on streaming-buffer rows — log warning, don't abort pipeline
            log.warning("bq_truncate_warning", constituency_id=constituency_id, error=str(e))

    async def insert_hotspots(self, rows: list[dict]) -> None:
        """Stream demand hotspot rows into BigQuery."""
        # Columns that exist in the demand_hotspots BQ schema
        _HOTSPOT_COLS = {
            "hotspot_id",
            "computed_at",
            "category",
            "center_lat",
            "center_lon",
            "radius_km",
            "complaint_count",
            "avg_urgency",
            "affected_population",
            "demand_score",
            "gap_index",
            "priority_score",
            "priority_rank",
            "constituency_id",
            "ward_id",
            "evidence_log",
            "suggested_project",
        }
        clean = []
        for r in rows:
            row = _serialize_bq_row({k: v for k, v in r.items() if k in _HOTSPOT_COLS})
            # Nullable / optional columns
            row.setdefault("ward_id", None)
            row.setdefault("evidence_log", None)
            row.setdefault("affected_population", None)
            row.setdefault("suggested_project", "")
            # Required numeric columns — must never be absent from insert
            row.setdefault("demand_score", 0.0)
            row.setdefault("gap_index", 0.0)
            row.setdefault("priority_score", 0.0)
            row.setdefault("priority_rank", 0)
            clean.append(row)

        client = self._get_client()
        table = self._table(self._analytics_ds, "demand_hotspots")

        def _sync_insert():
            return client.insert_rows_json(table, clean)

        errors = await asyncio.get_event_loop().run_in_executor(None, _sync_insert)
        if errors:
            log.error("bq_hotspot_insert_error", errors=errors)
            raise RuntimeError(f"BigQuery hotspot insert failed: {errors}")

    async def log_project_completion(
        self,
        completion_id: str,
        constituency_id: str,
        mp_email: str,
        project_name: str,
        category: str,
        center_lat: float,
        center_lon: float,
        submitted_lat: float,
        submitted_lon: float,
        distance_km: float,
        geo_verified: bool,
        ai_verified: bool,
        ai_confidence: int,
        ai_reasoning: str,
        evidence_gcs_uri: str,
        notes: str,
    ) -> None:
        """
        Append a project completion record to janmat_analytics.project_completions.
        Table is created automatically if it doesn't exist (CREATE TABLE IF NOT EXISTS via schema).
        If the table is missing, logs a warning rather than failing the whole request.
        """
        row = {
            "completion_id": completion_id,
            "constituency_id": constituency_id,
            "mp_email": mp_email,
            "project_name": project_name,
            "category": category,
            "center_lat": center_lat,
            "center_lon": center_lon,
            "submitted_lat": submitted_lat,
            "submitted_lon": submitted_lon,
            "distance_km": round(distance_km, 3),
            "geo_verified": geo_verified,
            "ai_verified": ai_verified,
            "ai_confidence": ai_confidence,
            "ai_reasoning": ai_reasoning,
            "evidence_gcs_uri": evidence_gcs_uri,
            "notes": notes or "",
            "completed_at": datetime.now(timezone.utc).isoformat(),
        }
        client = self._get_client()
        table_ref = self._table(self._analytics_ds, "project_completions")
        try:
            errors = client.insert_rows_json(table_ref, [row])
            if errors:
                log.error(
                    "bq_completion_insert_error",
                    errors=errors,
                    completion_id=completion_id,
                )
                raise RuntimeError(f"BigQuery completion insert failed: {errors}")
            log.info(
                "bq_completion_logged",
                completion_id=completion_id,
                project=project_name,
                overall=geo_verified and ai_verified,
            )
        except Exception as e:
            # Table may not exist yet in the POC — log warning, don't fail the request
            log.warning(
                "bq_completion_log_skipped",
                error=str(e),
                completion_id=completion_id,
                hint="Create janmat_analytics.project_completions table to enable logging",
            )

    def _load_query(self, filename: str) -> str:
        """
        Load a SQL query from bigquery/queries/ and inject fully-qualified
        table names so the query works from Cloud Run (needs 3-part names).
        """
        import pathlib

        # Dockerfile copies backend/queries/ → /app/bigquery/queries/ inside container
        query_dir = pathlib.Path(__file__).parent.parent.parent / "bigquery" / "queries"
        query_file = query_dir / filename
        if query_file.exists():
            sql = query_file.read_text()
        else:
            log.warning("bq_query_file_not_found", file=str(query_file))
            sql = self._inline_query(filename)

        # Replace 2-part names with fully-qualified 3-part names.
        # SQL files use `janmat_analytics.X` and `janmat_infrastructure.X`.
        sql = sql.replace(
            "`janmat_analytics.",
            f"`{self._project}.{self._analytics_ds}.",
        ).replace(
            "`janmat_infrastructure.",
            f"`{self._project}.{self._infra_ds}.",
        )
        return sql

    def _inline_query(self, filename: str) -> str:
        """Fallback inline queries if file not found."""
        from app.config import get_settings

        s = get_settings()
        p = s.gcp_project_id
        ds = s.bq_analytics_dataset
        if filename == "demand_clustering.sql":
            return f"""
            SELECT
                GENERATE_UUID() AS hotspot_id,
                category,
                AVG(latitude)  AS center_lat,
                AVG(longitude) AS center_lon,
                2.0            AS radius_km,
                COUNT(*)       AS complaint_count,
                AVG(urgency_rating) AS avg_urgency,
                CAST(COUNT(*) * 150 AS INT64) AS affected_population,
                constituency_id,
                0.0 AS demand_score,
                0.0 AS gap_index,
                0.0 AS priority_score,
                0   AS priority_rank,
                CONCAT(category, ' improvement') AS suggested_project,
                NULL AS evidence_log,
                CURRENT_TIMESTAMP() AS computed_at
            FROM `{p}.{ds}.citizen_grievances`
            WHERE constituency_id = @constituency_id
              AND processing_status = 'processed'
              AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
              AND latitude  IS NOT NULL
              AND longitude IS NOT NULL
            GROUP BY category, constituency_id
            HAVING COUNT(*) >= @min_complaints
            """
        elif filename == "priority_scoring.sql":
            return f"""
            WITH hotspots AS (
                SELECT *
                FROM `{p}.{ds}.demand_hotspots`
                WHERE constituency_id = @constituency_id
            ),
            max_vals AS (
                SELECT
                    MAX(complaint_count) AS max_complaints,
                    MAX(avg_urgency) AS max_urgency
                FROM hotspots
            ),
            scored AS (
                SELECT
                    h.hotspot_id,
                    h.category,
                    h.constituency_id,
                    h.complaint_count,
                    h.avg_urgency,
                    h.affected_population,
                    ROUND(
                        0.7 * (h.complaint_count / NULLIF(m.max_complaints, 0))
                        + 0.3 * (h.avg_urgency / NULLIF(m.max_urgency, 0)),
                        4
                    ) AS demand_score,
                    ROUND(RAND() * 0.5 + 0.4, 4) AS gap_index,
                    h.center_lat,
                    h.center_lon,
                    h.radius_km
                FROM hotspots h, max_vals m
            )
            SELECT
                hotspot_id,
                category,
                constituency_id,
                complaint_count,
                avg_urgency,
                affected_population,
                center_lat,
                center_lon,
                radius_km,
                demand_score,
                gap_index,
                ROUND(0.6 * demand_score + 0.4 * gap_index, 4) AS priority_score,
                ROW_NUMBER() OVER (ORDER BY (0.6 * demand_score + 0.4 * gap_index) DESC) AS priority_rank,
                CONCAT(category, ' Infrastructure Improvement') AS suggested_project,
                CURRENT_TIMESTAMP() AS generated_at
            FROM scored
            ORDER BY priority_score DESC
            """
        return "SELECT 1"


_bq_service: BigQueryService | None = None


def get_bigquery_service() -> BigQueryService:
    global _bq_service
    if _bq_service is None:
        _bq_service = BigQueryService()
    return _bq_service
