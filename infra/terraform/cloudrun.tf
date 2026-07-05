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
      min_instance_count = 0 # Scale to zero overnight
      max_instance_count = 3 # Cap for POC budget
    }

    vpc_access {
      connector = google_vpc_access_connector.janmat_connector.id
      egress    = "PRIVATE_RANGES_ONLY" # Only route private IPs through VPC (Cloud SQL)
    }

    containers {
      # Placeholder image — deploy.yml replaces this via gcloud run deploy
      # lifecycle.ignore_changes below ensures terraform never reverts it
      image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true # Only allocate CPU during request processing (saves cost)
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
      env {
        name  = "JANMAT_ETL_URL"
        value = google_cloud_run_v2_service.etl.uri
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
    # CI/CD deploy workflow manages image, env vars, and scaling — Terraform must not touch them
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
      template[0].scaling,
    ]
  }
}

# Allow public (unauthenticated) access to backend Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─────────────────────────────────────────
# Cloud Run — MP Dashboard (Node.js)
# ─────────────────────────────────────────
resource "google_cloud_run_v2_service" "dashboard" {
  name     = "janmat-dashboard"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.backend.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        cpu_idle = true
      }

      ports {
        container_port = 8080
      }

      # Backend URL — hardcoded so dashboard always hits production API
      env {
        name  = "JANMAT_API_URL"
        value = "https://janmat-backend-w2w3osjaua-el.a.run.app"
      }
      env {
        name  = "ALLOWED_MP_EMAILS"
        value = "quantumduobuilder@gmail.com,richardjoy9946@gmail.com,mp@janmat.demo"
      }
      env {
        name  = "DEMO_USER"
        value = "mp@janmat.demo"
      }
      env {
        name  = "DEMO_PASS"
        value = "JanMat@2025!"
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }

      # Secrets
      env {
        name = "SESSION_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.session_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.google_client_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.google_client_secret.secret_id
            version = "latest"
          }
        }
      }
      # GOOGLE_CALLBACK_URL is set via gcloud after first deploy (URL known then)
    }
  }

  depends_on = [
    google_project_service.apis,
    google_service_account.backend,
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }
}

# Allow public access to dashboard
resource "google_cloud_run_v2_service_iam_member" "dashboard_public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.dashboard.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Grant dashboard service account access to its secrets
resource "google_secret_manager_secret_iam_member" "dashboard_session_secret" {
  secret_id = google_secret_manager_secret.session_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "dashboard_google_client_id" {
  secret_id = google_secret_manager_secret.google_client_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "dashboard_google_client_secret" {
  secret_id = google_secret_manager_secret.google_client_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# ─────────────────────────────────────────
# Cloud Run — ETL Pipeline Service
# ─────────────────────────────────────────
resource "google_cloud_run_v2_service" "etl" {
  name     = "janmat-etl"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.backend.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      ports {
        container_port = 8000
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.media.name
      }
      env {
        name  = "GCS_UPLOAD_FOLDER"
        value = "uploads"
      }
      env {
        name  = "BIGQUERY_DATASET"
        value = google_bigquery_dataset.analytics.dataset_id
      }
      env {
        name  = "BIGQUERY_TABLE_GRIEVANCES"
        value = "citizen_grievances"
      }
      env {
        name  = "BIGQUERY_TABLE_AUDIT"
        value = "pipeline_audit"
      }
      env {
        name  = "PUBSUB_TOPIC_SUBMISSIONS"
        value = google_pubsub_topic.grievance_submitted.name
      }
      env {
        name  = "PUBSUB_TOPIC_DLQ"
        value = google_pubsub_topic.grievance_dlq.name
      }
      env {
        name  = "PUBSUB_SUBSCRIPTION"
        value = "grievance-processor-sub"
      }
      env {
        name  = "GEMINI_MODEL"
        value = var.gemini_model
      }
      env {
        name  = "ENVIRONMENT"
        value = "production"
      }
      env {
        name  = "DEBUG"
        value = "false"
      }
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_service_account.backend,
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }
}

# ETL is public — dashboard and backend both call it directly
resource "google_cloud_run_v2_service_iam_member" "etl_public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.etl.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
