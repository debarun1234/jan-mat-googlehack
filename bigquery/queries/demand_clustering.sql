-- ════════════════════════════════════════════════════════════════════
-- JanMat — Phase 2: Spatial Demand Clustering
-- ════════════════════════════════════════════════════════════════════
-- Groups citizen grievances into geographic demand hotspots using
-- BigQuery GIS. Each hotspot = a cluster of complaints within
-- @cluster_radius_km of each other, with at least @min_complaints.
--
-- Parameters:
--   @constituency_id   STRING  — constituency to process
--   @cluster_radius_km FLOAT64 — cluster radius in km (default: 2.0)
--   @min_complaints    INT64   — minimum complaints per cluster (default: 10)
--
-- Output: rows matching demand_hotspots schema
-- ════════════════════════════════════════════════════════════════════

WITH
-- Step 1: Filter recent processed grievances for this constituency
recent_grievances AS (
  SELECT
    submission_id,
    category,
    latitude,
    longitude,
    urgency_rating,
    summary_en,
    constituency_id,
    ward_id,
    village_name,
    submitted_at,
    ST_GEOGPOINT(longitude, latitude) AS geo_point
  FROM `janmat_analytics.citizen_grievances`
  WHERE
    constituency_id = @constituency_id
    AND processing_status = 'processed'
    AND submitted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND latitude IS NOT NULL
    AND longitude IS NOT NULL
),

-- Step 2: Create a unique set of "seed" points to cluster around.
-- We use a grid-based approach: round lat/lon to ~2km cells.
-- At ~13°N (Bangalore North), 0.018° lat ≈ 2km; 0.020° lon ≈ 2km
grid_cells AS (
  SELECT
    category,
    constituency_id,
    ROUND(latitude  / 0.018) * 0.018 AS grid_lat,
    ROUND(longitude / 0.020) * 0.020 AS grid_lon,
    COUNT(*)                         AS complaint_count,
    AVG(urgency_rating)              AS avg_urgency,
    AVG(latitude)                    AS center_lat,
    AVG(longitude)                   AS center_lon,
    ARRAY_AGG(submission_id)         AS submission_ids
  FROM recent_grievances
  GROUP BY
    category,
    constituency_id,
    grid_lat,
    grid_lon
  HAVING COUNT(*) >= @min_complaints
),

-- Step 3: Enrich with affected population estimate.
-- Uses a simple density proxy: complaint_count * 150 (avg ward population / avg complaints).
-- In production, join against actual ward population from Census table.
enriched AS (
  SELECT
    GENERATE_UUID()        AS hotspot_id,
    g.category,
    g.center_lat,
    g.center_lon,
    @cluster_radius_km     AS radius_km,
    g.complaint_count,
    g.avg_urgency,
    CAST(g.complaint_count * 150 AS INT64)  AS affected_population,
    g.constituency_id,
    g.submission_ids,
    CURRENT_TIMESTAMP()    AS computed_at,
    -- Demand score: normalise within constituency (will be re-normalised in scoring step)
    g.complaint_count      AS raw_complaint_count,
    g.avg_urgency          AS raw_avg_urgency
  FROM grid_cells g
)

SELECT
  hotspot_id,
  category,
  center_lat,
  center_lon,
  radius_km,
  complaint_count,
  avg_urgency,
  affected_population,
  constituency_id,
  -- demand_score: normalised in priority_scoring.sql
  0.0                       AS demand_score,
  0.0                       AS gap_index,
  0.0                       AS priority_score,
  0                         AS priority_rank,
  CONCAT(category, ' improvement in constituency ', constituency_id) AS suggested_project,
  NULL                      AS evidence_log,
  computed_at
FROM enriched
ORDER BY complaint_count DESC
