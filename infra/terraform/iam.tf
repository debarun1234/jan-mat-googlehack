# ─────────────────────────────────────────
# Service Accounts
# ─────────────────────────────────────────

# Backend service account — used by Cloud Run FastAPI service
resource "google_service_account" "backend" {
  account_id   = "janmat-backend"
  display_name = "JanMat Backend Service Account"
  description  = "Used by Cloud Run FastAPI service to access all GCP resources"
}

# Scheduler service account — used by Cloud Scheduler to stop/start DB
resource "google_service_account" "scheduler" {
  account_id   = "janmat-scheduler"
  display_name = "JanMat Scheduler Service Account"
  description  = "Used by Cloud Scheduler for kill/restart DB jobs"
}

# GitHub CI service account — used by Workload Identity Federation
resource "google_service_account" "github_ci" {
  account_id   = "janmat-github-ci"
  display_name = "JanMat GitHub Actions CI"
  description  = "Used by GitHub Actions via Workload Identity Federation"
}

locals {
  github_ci_roles = [
    "roles/run.developer",
    "roles/run.admin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
    "roles/pubsub.editor",
    "roles/cloudsql.client",
    "roles/secretmanager.admin",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/cloudbuild.builds.editor",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/resourcemanager.projectIamAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/artifactregistry.writer",
  ]
}

resource "google_project_iam_member" "github_ci_roles" {
  for_each = toset(local.github_ci_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.github_ci.email}"
}

# ─────────────────────────────────────────
# IAM Bindings — Backend SA
# ─────────────────────────────────────────
locals {
  backend_roles = [
    "roles/bigquery.dataEditor",          # Read/write BigQuery tables
    "roles/bigquery.jobUser",             # Run BigQuery jobs
    "roles/cloudsql.client",              # Connect to Cloud SQL
    "roles/storage.objectCreator",        # Upload media to GCS
    "roles/storage.objectViewer",         # Read media from GCS
    "roles/pubsub.publisher",             # Publish to Pub/Sub topics
    "roles/pubsub.subscriber",            # Subscribe to Pub/Sub topics
    "roles/secretmanager.secretAccessor", # Read secrets
    "roles/aiplatform.user",              # Vertex AI / Gemini API
    "roles/run.invoker",                  # Allow Cloud Run to call itself (service-to-service)
  ]
}

resource "google_project_iam_member" "backend_roles" {
  for_each = toset(local.backend_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# ─────────────────────────────────────────
# IAM Bindings — Scheduler SA
# ─────────────────────────────────────────
resource "google_project_iam_member" "scheduler_sqladmin" {
  project = var.project_id
  role    = "roles/cloudsql.admin" # Required to patch instance activation policy
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# Allow Pub/Sub to push to Cloud Run (for push subscriptions if needed later)
resource "google_project_iam_member" "pubsub_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ─────────────────────────────────────────
# IAM Bindings — Cloud Build (Compute Engine default SA)
# Cloud Build uses {PROJECT_NUMBER}-compute@developer.gserviceaccount.com
# by default. Grant it push access to Artifact Registry and Cloud Logging.
# ─────────────────────────────────────────
resource "google_project_iam_member" "cloudbuild_compute_roles" {
  for_each = toset([
    "roles/artifactregistry.writer", # Push images to gcr.io / Artifact Registry
    "roles/logging.logWriter",       # Write Cloud Build logs
    "roles/storage.admin",           # Read/write _cloudbuild GCS bucket
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Allow Cloud SQL to write to Secret Manager (for connection string)
resource "google_secret_manager_secret_iam_member" "backend_db_url" {
  secret_id = google_secret_manager_secret.db_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# ─────────────────────────────────────────
# Data source: project metadata
# ─────────────────────────────────────────
data "google_project" "project" {
  project_id = var.project_id
}
