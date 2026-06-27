terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Uncomment to use GCS backend for state (recommended for team)
  # backend "gcs" {
  #   bucket = "janmat-tfstate"
  #   prefix = "terraform/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ─────────────────────────────────────────
# Enable all required GCP APIs
# ─────────────────────────────────────────
locals {
  required_apis = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "aiplatform.googleapis.com",        # Vertex AI / Gemini
    "speech.googleapis.com",            # Cloud Speech-to-Text
    "translate.googleapis.com",         # Translation API
    "maps-backend.googleapis.com",      # Google Maps Platform
    "geocoding-backend.googleapis.com", # Geocoding API
    "vpcaccess.googleapis.com",         # Serverless VPC Access
    "servicenetworking.googleapis.com", # Private service connections
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false

  timeouts {
    create = "10m"
  }
}
