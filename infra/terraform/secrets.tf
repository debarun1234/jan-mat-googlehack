# ─────────────────────────────────────────
# Secret Manager — All API keys and credentials
# Populate values manually after terraform apply:
#   gcloud secrets versions add <secret-id> --data-file=-
# ─────────────────────────────────────────

# Google Maps / Geocoding API key
resource "google_secret_manager_secret" "maps_api_key" {
  secret_id = "janmat-maps-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# Gemini API key (if using AI Studio key instead of Vertex AI SA auth)
# For POC on Vertex AI, SA auth is preferred — this is a fallback
resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "janmat-gemini-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# JWT secret for MP dashboard auth
resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "janmat-jwt-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# Session secret for MP Dashboard (Node.js express-session)
resource "google_secret_manager_secret" "session_secret" {
  secret_id = "janmat-session-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# Google OAuth credentials for MP Dashboard
resource "google_secret_manager_secret" "google_client_id" {
  secret_id = "janmat-google-client-id"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "google_client_secret" {
  secret_id = "janmat-google-client-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# db_url secret is created in database.tf (has the actual value from Terraform)

# ─────────────────────────────────────────
# Output secret names for reference
# ─────────────────────────────────────────
# After apply, populate manually:
#
# Maps API key:
#   echo -n "YOUR_MAPS_API_KEY" | gcloud secrets versions add janmat-maps-api-key --data-file=-
#
# JWT secret:
#   openssl rand -hex 32 | gcloud secrets versions add janmat-jwt-secret --data-file=-
#
# Google OAuth:
#   echo -n "CLIENT_ID" | gcloud secrets versions add janmat-google-client-id --data-file=-
#   echo -n "CLIENT_SECRET" | gcloud secrets versions add janmat-google-client-secret --data-file=-
