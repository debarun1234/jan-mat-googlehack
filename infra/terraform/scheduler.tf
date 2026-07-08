# ─────────────────────────────────────────
# Cloud Scheduler — DB Kill/Restart
#
# Cloud SQL Admin API: PATCH instance to toggle activationPolicy
#   NEVER  = stopped (no compute cost)
#   ALWAYS = running
#
# IST = UTC+5:30
# Stop  at 11:00 PM IST = 17:30 UTC  →  "30 17 * * *"
# Start at  6:00 AM IST = 00:30 UTC  →  "30 0  * * *"
# Downtime window: 11 PM – 6 AM IST (7 hours)
# ─────────────────────────────────────────

# STOP: 11:00 PM IST every night
resource "google_cloud_scheduler_job" "stop_db" {
  name             = "janmat-stop-db"
  description      = "Stop Cloud SQL to save credits overnight"
  schedule         = var.db_stop_schedule # "30 17 * * *" (UTC)
  time_zone        = "Asia/Kolkata"
  attempt_deadline = "30s"

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.janmat_db.name}"

    body = base64encode(jsonencode({
      settings = {
        activationPolicy = "NEVER"
        tier             = "db-f1-micro"
      }
    }))

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.apis,
    google_sql_database_instance.janmat_db,
  ]
}

# START: 6:00 AM IST every morning
resource "google_cloud_scheduler_job" "start_db" {
  name             = "janmat-start-db"
  description      = "Start Cloud SQL in the morning"
  schedule         = var.db_start_schedule # "30 0 * * *" (UTC)
  time_zone        = "Asia/Kolkata"
  attempt_deadline = "30s"

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.janmat_db.name}"

    body = base64encode(jsonencode({
      settings = {
        activationPolicy = "ALWAYS"
        tier             = "db-f1-micro"
      }
    }))

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.apis,
    google_sql_database_instance.janmat_db,
  ]
}

# ─────────────────────────────────────────
# Manual override scripts (in /infra/scripts/)
# These are referenced here for documentation
# ─────────────────────────────────────────
# To manually stop DB:
#   gcloud sql instances patch janmat-db-poc --activation-policy=NEVER
#
# To manually start DB:
#   gcloud sql instances patch janmat-db-poc --activation-policy=ALWAYS
#
# To trigger scheduler job immediately (for testing):
#   gcloud scheduler jobs run janmat-stop-db --location=asia-south1
#   gcloud scheduler jobs run janmat-start-db --location=asia-south1
