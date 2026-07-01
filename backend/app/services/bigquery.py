"""
BigQuery service — streaming insert + analytical queries.

Tables:
  janmat_analytics.citizen_grievances   — Phase 1 output
  janmat_analytics.demand_hotspots      — Phase 2 clustering output
  janmat_analytics.priority_scores      — Phase 2 ranked output
  janmat_infrastructure.public_infrastructure  — Census / NFHS reference data
"""

from datetime import datetime, timezone

import structlog
from google.cloud import bigquery
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings
from app.services.gemini import StructuredGrievance

log = structlog.get_logger()


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
        errors = client.insert_rows_json(
            self._table(self._analytics_ds, "citizen_grievances"),
            [row],
        )
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
                bigquery.ScalarQueryParameter("min_complaints", "INT64", 10),
            ]
        )
        job = client.query(sql, job_config=job_config)
        results = job.result()
        rows = [dict(row) for row in results]
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
        job = client.query(sql, job_config=job_config)
        results = job.result()
        rows = [dict(row) for row in results]
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
        client = self._get_client()
        job = client.query(
            sql,
            job_config=bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    bigquery.ScalarQueryParameter("category", "STRING", category),
                ]
            ),
        )
        rows = [dict(r) for r in job.result()]
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

    async def get_priority_ranking(
        self, constituency_id: str, limit: int = 10
    ) -> list[dict]:
        """
        Fetch the latest ranked project list for the MP dashboard.
        """
        sql = f"""
        SELECT
            ps.hotspot_id,
            ps.category,
            ps.priority_rank,
            ps.priority_score,
            ps.demand_score,
            ps.gap_index,
            ps.suggested_project,
            ps.generated_at,
            dh.complaint_count,
            dh.avg_urgency,
            dh.affected_population,
            dh.center_lat,
            dh.center_lon,
            dh.radius_km
        FROM `{self._table(self._analytics_ds, "priority_scores")}` ps
        JOIN `{self._table(self._analytics_ds, "demand_hotspots")}` dh
          ON ps.hotspot_id = dh.hotspot_id
        WHERE ps.constituency_id = @constituency_id
          AND DATE(ps.generated_at) = (
            SELECT MAX(DATE(generated_at))
            FROM `{self._table(self._analytics_ds, "priority_scores")}`
            WHERE constituency_id = @constituency_id
          )
        ORDER BY ps.priority_rank ASC
        LIMIT @limit
        """
        client = self._get_client()
        job = client.query(
            sql,
            job_config=bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                    bigquery.ScalarQueryParameter("limit", "INT64", limit),
                ]
            ),
        )
        rows = [dict(r) for r in job.result()]
        log.info("bq_ranking_fetched", constituency_id=constituency_id, rows=len(rows))
        return rows

    async def get_heatmap_data(self, constituency_id: str) -> list[dict]:
        """
        Fetch lat/lon + weight for Google Maps heatmap layer.
        """
        sql = f"""
        SELECT
            center_lat AS lat,
            center_lon AS lng,
            complaint_count AS weight,
            category,
            avg_urgency
        FROM `{self._table(self._analytics_ds, "demand_hotspots")}`
        WHERE constituency_id = @constituency_id
        ORDER BY complaint_count DESC
        LIMIT 500
        """
        client = self._get_client()
        job = client.query(
            sql,
            job_config=bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter(
                        "constituency_id", "STRING", constituency_id
                    ),
                ]
            ),
        )
        return [dict(r) for r in job.result()]

    async def insert_priority_scores(self, rows: list[dict]) -> None:
        """Stream priority score rows into BigQuery."""
        client = self._get_client()
        errors = client.insert_rows_json(
            self._table(self._analytics_ds, "priority_scores"),
            rows,
        )
        if errors:
            log.error("bq_priority_insert_error", errors=errors)
            raise RuntimeError(f"BigQuery priority insert failed: {errors}")

    async def insert_hotspots(self, rows: list[dict]) -> None:
        """Stream demand hotspot rows into BigQuery."""
        client = self._get_client()
        errors = client.insert_rows_json(
            self._table(self._analytics_ds, "demand_hotspots"),
            rows,
        )
        if errors:
            log.error("bq_hotspot_insert_error", errors=errors)
            raise RuntimeError(f"BigQuery hotspot insert failed: {errors}")

    def _load_query(self, filename: str) -> str:
        """Load a SQL query from bigquery/queries/."""
        import pathlib

        # /app/app/services/bigquery.py → 3x parent → /app → bigquery/queries
        # (build context = project root; COPY bigquery/queries/ ./bigquery/queries/)
        query_dir = pathlib.Path(__file__).parent.parent.parent / "bigquery" / "queries"
        query_file = query_dir / filename
        if query_file.exists():
            return query_file.read_text()
        # Fallback: inline query (used in tests / minimal deploys)
        log.warning("bq_query_file_not_found", file=str(query_file))
        return self._inline_query(filename)

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
                AVG(latitude) AS center_lat,
                AVG(longitude) AS center_lon,
                2.0 AS radius_km,
                COUNT(*) AS complaint_count,
                AVG(urgency_rating) AS avg_urgency,
                constituency_id,
                CURRENT_TIMESTAMP() AS computed_at
            FROM `{p}.{ds}.citizen_grievances`
            WHERE constituency_id = @constituency_id
              AND processing_status = 'processed'
              AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
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
                    -- Demand score: normalised complaint volume × urgency
                    ROUND(
                        0.7 * (h.complaint_count / NULLIF(m.max_complaints, 0))
                        + 0.3 * (h.avg_urgency / NULLIF(m.max_urgency, 0)),
                        4
                    ) AS demand_score,
                    -- Gap index: placeholder, enriched by infra cross-reference
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
