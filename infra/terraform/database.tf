# ─────────────────────────────────────────
# Cloud SQL — PostgreSQL 15
# db-f1-micro (~$7/month), private IP only
# Stopped overnight via Cloud Scheduler
# ─────────────────────────────────────────
resource "google_sql_database_instance" "janmat_db" {
  name             = "janmat-db-${var.environment}"
  database_version = "POSTGRES_15"
  region           = var.region

  deletion_protection = false # POC: allow easy teardown

  settings {
    tier              = "db-f1-micro" # 1 shared vCPU, 614MB RAM — cheapest tier
    availability_type = "ZONAL"       # No HA = saves cost (single zone)
    disk_size         = 10            # 10GB SSD minimum
    disk_type         = "PD_SSD"
    disk_autoresize   = false # Prevent accidental storage expansion

    # NEVER = stopped, ALWAYS = running
    # Cloud Scheduler toggles this overnight
    activation_policy = "ALWAYS"

    ip_configuration {
      ipv4_enabled                                  = false # Private IP only (no public exposure)
      private_network                               = google_compute_network.janmat_vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled    = false # Disabled for POC cost saving
      start_time = "02:00"
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 2
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "50" # f1-micro default is 25; bump slightly for concurrent Cloud Run instances
    }

    database_flags {
      name  = "log_checkpoints"
      value = "off"
    }

    insights_config {
      query_insights_enabled = false # Saves cost
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.apis,
  ]
}

# Primary database
resource "google_sql_database" "janmat" {
  name     = var.db_name
  instance = google_sql_database_instance.janmat_db.name
}

# Application user
resource "google_sql_user" "janmat_user" {
  name     = var.db_user
  instance = google_sql_database_instance.janmat_db.name
  password = var.db_password
}

# Store connection string in Secret Manager
resource "google_secret_manager_secret" "db_url" {
  secret_id = "janmat-db-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "postgresql+asyncpg://${var.db_user}:${var.db_password}@${google_sql_database_instance.janmat_db.private_ip_address}:5432/${var.db_name}"
}
