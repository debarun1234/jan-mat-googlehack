output "cloud_run_url" {
  description = "Public URL of the JanMat backend API"
  value       = google_cloud_run_v2_service.backend.uri
}

output "cloud_sql_private_ip" {
  description = "Private IP of Cloud SQL instance (accessible from Cloud Run via VPC)"
  value       = google_sql_database_instance.janmat_db.private_ip_address
  sensitive   = true
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name (for gcloud commands)"
  value       = google_sql_database_instance.janmat_db.name
}

output "gcs_media_bucket" {
  description = "GCS bucket name for citizen media uploads"
  value       = google_storage_bucket.media.name
}

output "bq_analytics_dataset" {
  description = "BigQuery analytics dataset ID"
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bq_infrastructure_dataset" {
  description = "BigQuery infrastructure dataset ID"
  value       = google_bigquery_dataset.infrastructure.dataset_id
}

output "backend_service_account" {
  description = "Backend service account email"
  value       = google_service_account.backend.email
}

output "vpc_connector_name" {
  description = "Serverless VPC connector name"
  value       = google_vpc_access_connector.janmat_connector.name
}

output "pubsub_topics" {
  description = "Pub/Sub topic names"
  value = {
    grievance_submitted = google_pubsub_topic.grievance_submitted.name
    processing_complete = google_pubsub_topic.processing_complete.name
    priority_updated    = google_pubsub_topic.priority_updated.name
    dlq                 = google_pubsub_topic.grievance_dlq.name
  }
}

output "db_kill_restart_info" {
  description = "Commands to manually stop/start the database"
  value       = <<-EOT
    STOP DB:  gcloud sql instances patch ${google_sql_database_instance.janmat_db.name} --activation-policy=NEVER
    START DB: gcloud sql instances patch ${google_sql_database_instance.janmat_db.name} --activation-policy=ALWAYS

    Automated schedule (IST):
      Stop:  11:00 PM  →  ${var.db_stop_schedule} UTC
      Start:  7:00 AM  →  ${var.db_start_schedule} UTC
  EOT
}
