# ─────────────────────────────────────────
# BigQuery Datasets
# ─────────────────────────────────────────
resource "google_bigquery_dataset" "analytics" {
  dataset_id                 = "janmat_analytics"
  friendly_name              = "JanMat Analytics"
  description                = "Citizen grievance analytics, demand hotspots, and priority scoring"
  location                   = "asia-south1"
  delete_contents_on_destroy = true # POC teardown safety

  default_table_expiration_ms = null # No auto-expiry

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "infrastructure" {
  dataset_id                 = "janmat_infrastructure"
  friendly_name              = "JanMat Public Infrastructure"
  description                = "Mock Census, NFHS, and infrastructure datasets for cross-referencing"
  location                   = "asia-south1"
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

# ─────────────────────────────────────────
# Table: citizen_grievances
# Phase 1 output — every parsed submission
# ─────────────────────────────────────────
resource "google_bigquery_table" "citizen_grievances" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "citizen_grievances"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "submitted_at"
  }

  clustering = ["category", "constituency_id"]

  schema = jsonencode([
    { name = "submission_id", type = "STRING", mode = "REQUIRED", description = "UUID for each submission" },
    { name = "submitted_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Ingestion timestamp" },
    { name = "input_type", type = "STRING", mode = "REQUIRED", description = "text | audio | image" },
    { name = "raw_input_gcs_uri", type = "STRING", mode = "NULLABLE", description = "GCS URI for audio/image files" },
    { name = "raw_text", type = "STRING", mode = "NULLABLE", description = "Citizen's raw text or transcribed audio" },
    { name = "source_language", type = "STRING", mode = "NULLABLE", description = "BCP-47 language code detected (e.g. hi, kn, ta)" },
    { name = "translated_text", type = "STRING", mode = "NULLABLE", description = "English translation of raw input" },
    # ── Gemini structured output ──
    { name = "category", type = "STRING", mode = "REQUIRED", description = "Education | Health | Roads | Water | Sanitation" },
    { name = "latitude", type = "FLOAT64", mode = "REQUIRED", description = "Extracted or GPS latitude" },
    { name = "longitude", type = "FLOAT64", mode = "REQUIRED", description = "Extracted or GPS longitude" },
    { name = "urgency_rating", type = "INT64", mode = "REQUIRED", description = "1 (low) to 5 (critical)" },
    { name = "summary_en", type = "STRING", mode = "REQUIRED", description = "Gemini English summary of the problem" },
    # ── Geo enrichment ──
    { name = "constituency_id", type = "STRING", mode = "NULLABLE", description = "Resolved constituency identifier" },
    { name = "ward_id", type = "STRING", mode = "NULLABLE", description = "Resolved ward/block identifier" },
    { name = "village_name", type = "STRING", mode = "NULLABLE", description = "Reverse geocoded village/area name" },
    # ── Processing metadata ──
    { name = "processing_status", type = "STRING", mode = "REQUIRED", description = "pending | processed | error" },
    { name = "gemini_model_used", type = "STRING", mode = "NULLABLE", description = "Model version used for parsing" },
    { name = "processing_latency_ms", type = "INT64", mode = "NULLABLE", description = "End-to-end processing time in ms" },
  ])
}

# ─────────────────────────────────────────
# Table: demand_hotspots
# Phase 2 output — spatial clusters
# ─────────────────────────────────────────
resource "google_bigquery_table" "demand_hotspots" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "demand_hotspots"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "computed_at"
  }

  schema = jsonencode([
    { name = "hotspot_id", type = "STRING", mode = "REQUIRED" },
    { name = "computed_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "category", type = "STRING", mode = "REQUIRED" },
    { name = "center_lat", type = "FLOAT64", mode = "REQUIRED" },
    { name = "center_lon", type = "FLOAT64", mode = "REQUIRED" },
    { name = "radius_km", type = "FLOAT64", mode = "REQUIRED" },
    { name = "complaint_count", type = "INT64", mode = "REQUIRED", description = "Total submissions in this cluster" },
    { name = "avg_urgency", type = "FLOAT64", mode = "REQUIRED" },
    { name = "affected_population", type = "INT64", mode = "NULLABLE", description = "Population in cluster radius from Census" },
    # ── Priority formula components ──
    { name = "demand_score", type = "FLOAT64", mode = "REQUIRED", description = "D = normalized complaint volume × avg_urgency" },
    { name = "gap_index", type = "FLOAT64", mode = "REQUIRED", description = "G = infrastructure deficit score from public datasets" },
    { name = "priority_score", type = "FLOAT64", mode = "REQUIRED", description = "P = 0.6×D + 0.4×G (population-normalized)" },
    { name = "priority_rank", type = "INT64", mode = "NULLABLE", description = "Rank within constituency (1 = highest priority)" },
    { name = "constituency_id", type = "STRING", mode = "REQUIRED" },
    { name = "ward_id", type = "STRING", mode = "NULLABLE" },
    { name = "evidence_log", type = "STRING", mode = "NULLABLE", description = "Gemini-generated Evidence Log for this project" },
    { name = "suggested_project", type = "STRING", mode = "NULLABLE", description = "e.g. High School Construction in Ward 4" },
  ])
}

# ─────────────────────────────────────────
# Table: public_infrastructure
# Mock Census / NFHS data — village level
# ─────────────────────────────────────────
resource "google_bigquery_table" "public_infrastructure" {
  dataset_id          = google_bigquery_dataset.infrastructure.dataset_id
  table_id            = "public_infrastructure"
  deletion_protection = false

  clustering = ["constituency_id", "category"]

  schema = jsonencode([
    { name = "village_id", type = "STRING", mode = "REQUIRED" },
    { name = "village_name", type = "STRING", mode = "REQUIRED" },
    { name = "latitude", type = "FLOAT64", mode = "REQUIRED" },
    { name = "longitude", type = "FLOAT64", mode = "REQUIRED" },
    { name = "constituency_id", type = "STRING", mode = "REQUIRED" },
    { name = "ward_id", type = "STRING", mode = "NULLABLE" },
    { name = "population", type = "INT64", mode = "REQUIRED" },
    { name = "category", type = "STRING", mode = "REQUIRED", description = "Education | Health | Roads | Water | Sanitation" },
    # Education
    { name = "primary_schools", type = "INT64", mode = "NULLABLE" },
    { name = "secondary_schools", type = "INT64", mode = "NULLABLE" },
    { name = "school_enrollment_rate", type = "FLOAT64", mode = "NULLABLE", description = "0.0 to 1.0" },
    { name = "nearest_secondary_school_km", type = "FLOAT64", mode = "NULLABLE" },
    { name = "teen_travel_distance_km", type = "FLOAT64", mode = "NULLABLE", description = "Avg distance teens travel for secondary school" },
    # Health
    { name = "health_centers", type = "INT64", mode = "NULLABLE" },
    { name = "hospital_beds_per_1000", type = "FLOAT64", mode = "NULLABLE" },
    { name = "nearest_hospital_km", type = "FLOAT64", mode = "NULLABLE" },
    # Roads
    { name = "road_quality_score", type = "FLOAT64", mode = "NULLABLE", description = "0 (no road) to 10 (excellent)" },
    { name = "paved_road_coverage_pct", type = "FLOAT64", mode = "NULLABLE" },
    # Water & Sanitation
    { name = "piped_water_access_pct", type = "FLOAT64", mode = "NULLABLE" },
    { name = "sanitation_coverage_pct", type = "FLOAT64", mode = "NULLABLE" },
    { name = "open_defecation_free", type = "BOOL", mode = "NULLABLE" },
    # Meta
    { name = "data_source", type = "STRING", mode = "REQUIRED", description = "Census2011 | NFHS5 | OpenStreetMap | Mock" },
    { name = "reference_year", type = "INT64", mode = "NULLABLE" },
    { name = "last_updated", type = "DATE", mode = "REQUIRED" },
  ])
}

# ─────────────────────────────────────────
# Table: priority_scores (final ranked list)
# Phase 3 input for MP Dashboard
# ─────────────────────────────────────────
resource "google_bigquery_table" "priority_scores" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "priority_scores"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "generated_at"
  }

  schema = jsonencode([
    { name = "score_id", type = "STRING", mode = "REQUIRED" },
    { name = "generated_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "constituency_id", type = "STRING", mode = "REQUIRED" },
    { name = "rank", type = "INT64", mode = "REQUIRED" },
    { name = "category", type = "STRING", mode = "REQUIRED" },
    { name = "suggested_project", type = "STRING", mode = "REQUIRED" },
    { name = "priority_score", type = "FLOAT64", mode = "REQUIRED" },
    { name = "demand_score", type = "FLOAT64", mode = "REQUIRED" },
    { name = "gap_index", type = "FLOAT64", mode = "REQUIRED" },
    { name = "complaint_count", type = "INT64", mode = "REQUIRED" },
    { name = "avg_urgency", type = "FLOAT64", mode = "REQUIRED" },
    { name = "center_lat", type = "FLOAT64", mode = "REQUIRED" },
    { name = "center_lon", type = "FLOAT64", mode = "REQUIRED" },
    { name = "evidence_log", type = "STRING", mode = "REQUIRED", description = "Gemini-generated grounded justification" },
    { name = "hotspot_id", type = "STRING", mode = "NULLABLE", description = "FK to demand_hotspots" },
  ])
}
