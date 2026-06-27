# ═══════════════════════════════════════════════════════════════════
#  GCS — All Cloud Storage buckets for JanMat
#  Everything Terraform-controlled. No manual bucket creation needed.
#
#  Buckets:
#    1. janmat-media-{project}   — citizen audio/image uploads
#    2. janmat-tfplans-{project} — terraform plan artifacts (CI/CD)
#    3. janmat-logs-{project}    — Cloud Run + Cloud SQL audit logs
#    4. janmat-exports-{project} — MP CSV/report exports
# ═══════════════════════════════════════════════════════════════════

locals {
  bucket_prefix = "janmat"
}

# ── 1. Media bucket — citizen audio / image submissions ─────────────
resource "google_storage_bucket" "media" {
  name                        = "${local.bucket_prefix}-media-${var.project_id}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true # POC: allow teardown

  # Move to Nearline after 7 days (50% cheaper)
  lifecycle_rule {
    condition { age = 7 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Delete after 30 days (cost control)
  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "POST", "PUT"]
    response_header = ["Content-Type", "Authorization"]
    max_age_seconds = 3600
  }

  versioning {
    enabled = false # No versioning for media (cost saving)
  }

  depends_on = [google_project_service.apis]
}

# ── 2. Terraform plans bucket — CI/CD plan artifacts ────────────────
#    terraform plan -out=tfplan saved here during PR
#    terraform apply pulls it on merge — ensures apply == reviewed plan
resource "google_storage_bucket" "tfplans" {
  name                        = "${local.bucket_prefix}-tfplans-${var.project_id}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true

  # Plans are only needed until applied — delete after 7 days
  lifecycle_rule {
    condition { age = 7 }
    action { type = "Delete" }
  }

  versioning {
    enabled = true # Keep plan history for audit
  }

  depends_on = [google_project_service.apis]
}

# Grant GitHub Actions SA access to upload/download plans
resource "google_storage_bucket_iam_member" "tfplans_github_ci" {
  bucket = google_storage_bucket.tfplans.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_ci.email}"
}

# ── 3. Logs bucket — audit + Cloud Run logs export ──────────────────
resource "google_storage_bucket" "logs" {
  name                        = "${local.bucket_prefix}-logs-${var.project_id}"
  location                    = var.region
  storage_class               = "COLDLINE" # Logs are rarely accessed
  uniform_bucket_level_access = true
  force_destroy               = true

  # Retain logs for 90 days (compliance baseline)
  lifecycle_rule {
    condition { age = 90 }
    action { type = "Delete" }
  }

  versioning {
    enabled = false
  }

  depends_on = [google_project_service.apis]
}

# ── 4. Exports bucket — MP CSV / report downloads ───────────────────
resource "google_storage_bucket" "exports" {
  name                        = "${local.bucket_prefix}-exports-${var.project_id}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true

  # Exports are transient — delete after 3 days
  lifecycle_rule {
    condition { age = 3 }
    action { type = "Delete" }
  }

  cors {
    origin          = ["*"]
    method          = ["GET"]
    response_header = ["Content-Type", "Content-Disposition"]
    max_age_seconds = 300
  }

  versioning {
    enabled = false
  }

  depends_on = [google_project_service.apis]
}

# ── IAM: Backend SA access ──────────────────────────────────────────

# Media bucket — backend can upload citizen submissions
resource "google_storage_bucket_iam_member" "media_backend_creator" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "media_backend_viewer" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backend.email}"
}

# Exports bucket — backend writes CSV reports
resource "google_storage_bucket_iam_member" "exports_backend_admin" {
  bucket = google_storage_bucket.exports.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

# Logs bucket — backend can write logs
resource "google_storage_bucket_iam_member" "logs_backend_creator" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.backend.email}"
}
