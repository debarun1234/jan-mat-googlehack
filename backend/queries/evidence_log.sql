-- ════════════════════════════════════════════════════════════════════
-- JanMat — Phase 3: Evidence Log Data Assembly
-- ════════════════════════════════════════════════════════════════════
-- Assembles all raw data needed for Gemini to generate the Evidence Log
-- for each ranked project. This query runs once per dashboard load
-- (or cached for 6h in Cloud SQL evidence_cache table).
--
-- The output is passed to gemini.generate_evidence_log() which
-- synthesises it into a human-readable 2-3 sentence justification.
--
-- Parameters:
--   @constituency_id   STRING
--   @limit             INT64   — number of top projects to assemble (default: 10)
-- ════════════════════════════════════════════════════════════════════

WITH

-- Latest priority scores
top_projects AS (
  SELECT
    ps.score_id,
    ps.hotspot_id,
    ps.category,
    ps.constituency_id,
    ps.priority_rank,
    ps.priority_score,
    ps.demand_score,
    ps.gap_index,
    ps.complaint_count,
    ps.avg_urgency,
    ps.affected_population,
    ps.center_lat,
    ps.center_lon,
    ps.radius_km,
    ps.suggested_project,
    ps.generated_at
  FROM `janmat_analytics.priority_scores` ps
  WHERE
    ps.constituency_id = @constituency_id
    AND DATE(ps.generated_at) = (
      SELECT MAX(DATE(generated_at))
      FROM `janmat_analytics.priority_scores`
      WHERE constituency_id = @constituency_id
    )
  ORDER BY ps.priority_rank ASC
  LIMIT @limit
),

-- Infrastructure facts per category (flattened for Gemini prompt)
infra_facts AS (
  SELECT
    pi.constituency_id,
    pi.category,
    -- Collect all metric key-value pairs as a single JSON string
    STRING_AGG(
      CONCAT(pi.metric_name, ': ', pi.metric_value, ' ', pi.metric_unit,
             ' (', pi.data_source, ', ', CAST(pi.reference_year AS STRING), ')'),
      ' | '
      ORDER BY pi.metric_name
    ) AS facts_summary
  FROM `janmat_infrastructure.public_infrastructure` pi
  WHERE pi.constituency_id = @constituency_id
  GROUP BY pi.constituency_id, pi.category
),

-- Complaint sample: top 3 most urgent complaints per category for context
complaint_samples AS (
  SELECT
    category,
    constituency_id,
    STRING_AGG(summary_en, ' | ' ORDER BY urgency_rating DESC LIMIT 3) AS sample_complaints
  FROM `janmat_analytics.citizen_grievances`
  WHERE
    constituency_id = @constituency_id
    AND processing_status = 'processed'
    AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY category, constituency_id
),

-- 30-day trend per category: is demand rising or falling?
demand_trend AS (
  SELECT
    category,
    constituency_id,
    -- Count in last 7 days vs. 8-30 days
    COUNTIF(submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))  AS last_7d,
    COUNTIF(submitted_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
            AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS prev_23d,
    COUNT(*) AS total_30d
  FROM `janmat_analytics.citizen_grievances`
  WHERE
    constituency_id = @constituency_id
    AND processing_status = 'processed'
    AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY category, constituency_id
)

SELECT
  tp.priority_rank,
  tp.hotspot_id,
  tp.score_id,
  tp.category,
  tp.constituency_id,
  tp.priority_score,
  tp.demand_score,
  tp.gap_index,
  tp.complaint_count,
  tp.avg_urgency,
  tp.affected_population,
  tp.center_lat,
  tp.center_lon,
  tp.radius_km,
  tp.suggested_project,
  tp.generated_at,

  -- Infrastructure facts for Gemini context
  COALESCE(inf.facts_summary, 'No infrastructure data available') AS infrastructure_facts,

  -- Sample complaints (anonymised)
  COALESCE(cs.sample_complaints, 'No samples available') AS complaint_samples,

  -- Trend indicator: RISING / STABLE / FALLING
  CASE
    WHEN t.last_7d > 0 AND t.prev_23d > 0
      AND (t.last_7d / t.prev_23d) > 1.5   THEN 'RISING'
    WHEN t.last_7d > 0 AND t.prev_23d > 0
      AND (t.last_7d / t.prev_23d) < 0.5   THEN 'FALLING'
    ELSE 'STABLE'
  END AS trend,
  COALESCE(t.last_7d, 0)   AS complaints_last_7d,
  COALESCE(t.total_30d, 0) AS complaints_last_30d

FROM top_projects tp
LEFT JOIN infra_facts inf
  ON tp.constituency_id = inf.constituency_id
  AND tp.category = inf.category
LEFT JOIN complaint_samples cs
  ON tp.constituency_id = cs.constituency_id
  AND tp.category = cs.category
LEFT JOIN demand_trend t
  ON tp.constituency_id = t.constituency_id
  AND tp.category = t.category
ORDER BY tp.priority_rank ASC
