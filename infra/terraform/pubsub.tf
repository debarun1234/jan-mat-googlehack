# ─────────────────────────────────────────
# Cloud Pub/Sub — Async event pipeline
# ─────────────────────────────────────────

# Topic 1: New grievance submitted (triggers Gemini processing)
resource "google_pubsub_topic" "grievance_submitted" {
  name = "grievance-submitted"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  depends_on = [google_project_service.apis]
}

# Pull subscription — used by the ETL when it manually polls (local dev / batch jobs)
resource "google_pubsub_subscription" "grievance_processor" {
  name  = "grievance-processor-sub"
  topic = google_pubsub_topic.grievance_submitted.name

  ack_deadline_seconds       = 60
  message_retention_duration = "600s"
  retain_acked_messages      = false

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.grievance_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }
}

# Push subscription — sends Pub/Sub messages directly to the ETL Cloud Run service
# This is the production path: backend publishes → Pub/Sub pushes → ETL processes
resource "google_pubsub_subscription" "grievance_processor_push" {
  name  = "grievance-processor-push-sub"
  topic = google_pubsub_topic.grievance_submitted.name

  ack_deadline_seconds       = 300 # ETL can take up to 5 min for heavy AI processing
  message_retention_duration = "600s"
  retain_acked_messages      = false

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.etl.uri}/api/v1/pubsub/push"

    oidc_token {
      service_account_email = google_service_account.backend.email
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.grievance_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "30s"
    maximum_backoff = "120s"
  }

  depends_on = [google_cloud_run_v2_service.etl]
}

# Topic 2: Processing complete (triggers analytics engine)
resource "google_pubsub_topic" "processing_complete" {
  name = "processing-complete"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_subscription" "analytics_trigger" {
  name  = "analytics-trigger-sub"
  topic = google_pubsub_topic.processing_complete.name

  ack_deadline_seconds       = 120 # Analytics engine can take longer
  message_retention_duration = "600s"
  retain_acked_messages      = false
}

# Topic 3: Priority score updated (triggers dashboard refresh / MP notification)
resource "google_pubsub_topic" "priority_updated" {
  name = "priority-updated"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_subscription" "dashboard_refresh" {
  name  = "dashboard-refresh-sub"
  topic = google_pubsub_topic.priority_updated.name

  ack_deadline_seconds       = 30
  message_retention_duration = "600s"
  retain_acked_messages      = false
}

# Dead Letter Queue topic
resource "google_pubsub_topic" "grievance_dlq" {
  name = "grievance-dlq"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_subscription" "grievance_dlq_sub" {
  name  = "grievance-dlq-sub"
  topic = google_pubsub_topic.grievance_dlq.name

  ack_deadline_seconds       = 600
  message_retention_duration = "604800s" # 7 days — review failed messages
}
