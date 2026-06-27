# ─────────────────────────────────────────
# Cloud Run — FastAPI Backend Service
# Scales to ZERO when idle (key cost saver)
# ─────────────────────────────────────────
resource "google_cloud_run_v2_service" "backend" {
  name     = "janmat-backend"
  location = var.region

  # Allow unauthenticated access (citizen app hits this directly)
  # Auth for MP dashboard endpoints is handled at application layer (JWT)
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.backend.email

    scaling {
      min_instance_count = 0  # Scale to zero overnight
      max_instance_count = 3  # Cap for POC budget
    }

    vpc_access {
      connector = google_vpc_access_connector.janmat_connector.id
      egress    = "PRIVATE_RANGES_ONLY" # Only route private IPs through VPC (Cloud SQL)
    }

    containers {
      # Image will be built and pushed during CI/CD — placeholder for now
      image = "gcr.io/${var.project_id}/janmat-backend:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true  # Only allocate CPU during request processing (saves cost)
      }

      # Startup probe — wait for FastAPI to be ready
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
        timeout_seconds       = 3
      }

      # Liveness probe
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 5
      }

      ports {
        container_port = 8080
      }

      # Environment variables (non-sensitive)
      # Match pydantic-settings field names (underscore → uppercase)
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "GEMINI_MODEL"
        value = var.gemini_model
      }
      env {
        name  = "BQ_ANALYTICS_DATASET"
        value = google_bigquery_dataset.analytics.dataset_id
      }
      env {
        name  = "BQ_INFRASTRUCTURE_DATASET"
        value = google_bigquery_dataset.infrastructure.dataset_id
      }
      env {
        name  = "GCS_MEDIA_BUCKET"
        value = google_storage_bucket.media.name
      }
      env {
        name  = "PUBSUB_TOPIC_GRIEVANCE_SUBMITTED"
        value = google_pubsub_topic.grievance_submitted.name
      }
      env {
        name  = "PUBSUB_TOPIC_PROCESSING_COMPLETE"
        value = google_pubsub_topic.processing_complete.name
      }
      env {
        name  = "PUBSUB_TOPIC_PRIORITY_UPDATED"
        value = google_pubsub_topic.priority_updated.name
      }
      env {
        name  = "CONSTITUENCY_ID"
        value = var.constituency_id
      }

      # Sensitive values from Secret Manager
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "MAPS_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.maps_api_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_vpc_access_connector.janmat_connector,
    google_service_account.backend,
  ]

  lifecycle {
    # Don't redeploy if only the image tag changes (CI/CD handles that)
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

# Allow public (unauthenticated) access to Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
