# ─────────────────────────────────────────
# Cloud Storage — Media bucket
# Audio, images, video from citizen submissions
# ─────────────────────────────────────────
resource "google_storage_bucket" "media" {
  name                        = "janmat-media-${var.project_id}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true # POC: allow teardown

  # Cost control: delete objects after 30 days
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Move to Nearline after 7 days (cheaper storage tier)
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "POST", "PUT"]
    response_header = ["Content-Type", "Authorization"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.apis]
}

# Subfolder structure (enforced via object naming convention, not actual folders)
# janmat-media-{project_id}/audio/{submission_id}.ogg
# janmat-media-{project_id}/images/{submission_id}.jpg
# janmat-media-{project_id}/processed/{submission_id}_transcript.txt
