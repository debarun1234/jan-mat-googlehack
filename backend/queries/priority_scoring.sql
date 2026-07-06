-- ════════════════════════════════════════════════════════════════════
-- JanMat — Phase 2: Priority Scoring
-- P = 0.6 × D (Demand Score) + 0.4 × G (Gap Index)
-- ════════════════════════════════════════════════════════════════════
-- Parameters:
--   @constituency_id   STRING  — constituency to rank
-- ════════════════════════════════════════════════════════════════════

WITH

-- Latest demand hotspots for this constituency
latest_hotspots AS (
  SELECT
    hotspot_id,
    category,
    center_lat,
    center_lon,
    radius_km,
    complaint_count,
    avg_urgency,
    COALESCE(affected_population, complaint_count * 150) AS affected_population,
    constituency_id,
    computed_at
  FROM `janmat_analytics.demand_hotspots`
  WHERE constituency_id = @constituency_id
    AND DATE(computed_at) = (
      SELECT MAX(DATE(computed_at))
      FROM `janmat_analytics.demand_hotspots`
      WHERE constituency_id = @constituency_id
    )
),

-- Infrastructure baseline — wide-format columns from public_infrastructure table.
-- Gap Index = how far below national benchmark (0 = no gap, 1 = severe gap).
-- LEFT JOIN used so scoring still works when infra table has no data (defaults to 0.5).
infra_baseline AS (
  SELECT
    constituency_id,
    category,
    AVG(
      CASE category
        WHEN 'Education' THEN
          -- Low enrollment rate → high gap
          GREATEST(0.0, 1.0 - COALESCE(school_enrollment_rate, 0.75))
        WHEN 'Health' THEN
          -- Few beds per 1000 → high gap (benchmark: 3.0 beds/1000)
          GREATEST(0.0, 1.0 - COALESCE(SAFE_DIVIDE(hospital_beds_per_1000, 3.0), 0.5))
        WHEN 'Roads' THEN
          -- Low quality score → high gap
          GREATEST(0.0, 1.0 - COALESCE(SAFE_DIVIDE(road_quality_score, 10.0), 0.5))
        WHEN 'Water' THEN
          -- Low piped access % → high gap
          GREATEST(0.0, 1.0 - COALESCE(SAFE_DIVIDE(piped_water_access_pct, 100.0), 0.5))
        WHEN 'Sanitation' THEN
          -- Low sanitation coverage → high gap
          GREATEST(0.0, 1.0 - COALESCE(SAFE_DIVIDE(sanitation_coverage_pct, 100.0), 0.5))
        ELSE 0.5
      END
    ) AS gap_index
  FROM `janmat_infrastructure.public_infrastructure`
  WHERE constituency_id = @constituency_id
  GROUP BY constituency_id, category
),

-- Demand score: complaint volume × urgency, population-normalised
demand_scored AS (
  SELECT
    h.*,
    SAFE_DIVIDE(h.complaint_count * h.avg_urgency, h.affected_population) * 1000 AS demand_per_1000,
    COALESCE(ib.gap_index, 0.5) AS gap_index   -- defaults to 0.5 when no infra data
  FROM latest_hotspots h
  LEFT JOIN infra_baseline ib
    ON h.constituency_id = ib.constituency_id
    AND h.category = ib.category
),

-- Normalise demand score 0..1 within constituency
demand_normalised AS (
  SELECT
    *,
    MAX(demand_per_1000) OVER () AS max_demand_per_1000
  FROM demand_scored
),

-- Final priority score: P = 0.6D + 0.4G
scored AS (
  SELECT
    GENERATE_UUID() AS score_id,
    hotspot_id,
    category,
    constituency_id,
    ROUND(SAFE_DIVIDE(demand_per_1000, NULLIF(max_demand_per_1000, 0)), 4) AS demand_score,
    ROUND(gap_index, 4) AS gap_index,
    ROUND(
      10 * (
        0.6 * SAFE_DIVIDE(demand_per_1000, NULLIF(max_demand_per_1000, 0))
        + 0.4 * gap_index
      ),
      3
    ) AS priority_score,
    complaint_count,
    avg_urgency,
    affected_population,
    center_lat,
    center_lon,
    radius_km,
    CURRENT_TIMESTAMP() AS generated_at
  FROM demand_normalised
)

SELECT
  score_id,
  hotspot_id,
  category,
  constituency_id,
  demand_score,
  gap_index,
  priority_score,
  ROW_NUMBER() OVER (ORDER BY priority_score DESC) AS priority_rank,
  complaint_count,
  avg_urgency,
  affected_population,
  center_lat,
  center_lon,
  radius_km,
  CASE category
    WHEN 'Education'   THEN 'School Construction / Expansion'
    WHEN 'Health'      THEN 'Primary Health Centre Upgrade'
    WHEN 'Roads'       THEN 'Road Repair and Paving'
    WHEN 'Water'       THEN 'Piped Water Supply Extension'
    WHEN 'Sanitation'  THEN 'Sanitation and ODF Program'
    WHEN 'Electricity' THEN 'Electricity Infrastructure Upgrade'
    ELSE CONCAT(category, ' Infrastructure Improvement')
  END AS suggested_project,
  '' AS evidence_log,
  generated_at
FROM scored
ORDER BY priority_score DESC
