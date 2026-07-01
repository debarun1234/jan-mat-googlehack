-- ════════════════════════════════════════════════════════════════════
-- JanMat — Phase 2: Priority Scoring
-- P = 0.6 × D (Demand Score) + 0.4 × G (Gap Index)
-- ════════════════════════════════════════════════════════════════════
-- Cross-references demand hotspots against public_infrastructure
-- baseline data to produce a population-normalised priority ranking.
--
-- Parameters:
--   @constituency_id   STRING  — constituency to rank
--
-- Key design decisions:
--   - Population normalisation prevents dense urban wards from always
--     outranking underserved rural areas (core anti-bias mechanism)
--   - Gap Index computed per category from Census/NFHS benchmarks
--   - Formula weights: Demand 60%, Infrastructure Gap 40%
--
-- Output: rows matching priority_scores schema
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
  WHERE
    constituency_id = @constituency_id
    -- Use only the most recent clustering run
    AND DATE(computed_at) = (
      SELECT MAX(DATE(computed_at))
      FROM `janmat_analytics.demand_hotspots`
      WHERE constituency_id = @constituency_id
    )
),

-- Infrastructure baseline facts per category
-- Gap Index = how far below national benchmark each category is
infra_baseline AS (
  SELECT
    constituency_id,
    category,
    -- Aggregate all metrics for a category into a gap score 0..1
    -- Higher = bigger gap vs. national norm
    AVG(
      CASE
        -- Education: gap = 1 if no school within 5km, 0 if within 1km
        WHEN metric_name = 'primary_school_count'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 3.0))
        WHEN metric_name = 'enrollment_rate_pct'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 95.0))
        WHEN metric_name = 'avg_travel_distance_km'
          THEN LEAST(1, SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 10.0))
        -- Health: gap = inverse of beds per 1000, capped
        WHEN metric_name = 'health_beds_per_1000'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 3.0))
        -- Roads: gap = 1 - quality score
        WHEN metric_name = 'road_quality_score'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 10.0))
        WHEN metric_name = 'paved_road_coverage_pct'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 100.0))
        -- Water: gap = inverse of piped access %
        WHEN metric_name = 'piped_water_access_pct'
          THEN GREATEST(0, 1 - SAFE_DIVIDE(CAST(metric_value AS FLOAT64), 100.0))
        -- Sanitation: gap = 1 if not ODF
        WHEN metric_name = 'open_defecation_free'
          THEN CASE WHEN LOWER(metric_value) = 'yes' THEN 0.0 ELSE 1.0 END
        -- Default: neutral gap
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
    -- Raw demand: volume weighted by urgency
    (h.complaint_count * h.avg_urgency) AS raw_demand,
    -- Population normalisation: per 1000 residents prevents urban bias
    SAFE_DIVIDE(h.complaint_count * h.avg_urgency, h.affected_population) * 1000 AS demand_per_1000,
    COALESCE(ib.gap_index, 0.5) AS gap_index
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

-- Final priority score: P = 0.6 × D + 0.4 × G
scored AS (
  SELECT
    GENERATE_UUID()     AS score_id,
    hotspot_id,
    category,
    constituency_id,
    -- D: normalised demand (0..1)
    ROUND(SAFE_DIVIDE(demand_per_1000, NULLIF(max_demand_per_1000, 0)), 4) AS demand_score,
    -- G: infrastructure gap (0..1)
    ROUND(gap_index, 4) AS gap_index,
    -- P = 0.6D + 0.4G scaled to 0..10
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
  -- Rank 1 = highest priority
  ROW_NUMBER() OVER (ORDER BY priority_score DESC) AS priority_rank,
  complaint_count,
  avg_urgency,
  affected_population,
  center_lat,
  center_lon,
  radius_km,
  -- Human-readable project name
  CASE category
    WHEN 'Education'   THEN 'School Construction / Expansion'
    WHEN 'Health'      THEN 'Primary Health Centre Upgrade'
    WHEN 'Roads'       THEN 'Road Repair and Paving'
    WHEN 'Water'       THEN 'Piped Water Supply Extension'
    WHEN 'Sanitation'  THEN 'Sanitation and ODF Program'
    ELSE CONCAT(category, ' Infrastructure Improvement')
  END AS suggested_project,
  NULL AS evidence_log,
  generated_at
FROM scored
ORDER BY priority_score DESC
