variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region (asia-south1 = Mumbai, closest to India)"
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-south1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "poc"
}

variable "db_password" {
  description = "Cloud SQL Postgres password for janmat_user"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Primary database name"
  type        = string
  default     = "janmat"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "janmat_user"
}

# Kill/restart schedule (IST = UTC+5:30)
variable "db_stop_schedule" {
  description = "Cron schedule to STOP Cloud SQL (UTC). Default: 11:00 PM IST = 17:30 UTC"
  type        = string
  default     = "30 17 * * *"
}

variable "db_start_schedule" {
  description = "Cron schedule to START Cloud SQL (UTC). Default: 7:00 AM IST = 01:30 UTC"
  type        = string
  default     = "30 1 * * *"
}

variable "gemini_model" {
  description = "Vertex AI Gemini model to use (flash = cheapest)"
  type        = string
  default     = "gemini-2.5-flash-lite"
}

variable "maps_api_key_secret" {
  description = "Secret Manager secret name for Google Maps API key"
  type        = string
  default     = "janmat-maps-api-key"
}

variable "constituency_id" {
  description = "Default constituency ID for demo (can be overridden per-request)"
  type        = string
  default     = "KA-BLR-NORTH-01"
}
