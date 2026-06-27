#!/usr/bin/env bash
# Grant a co-developer the minimum IAM roles needed for JanMat POC.
# Usage:  ./infra/scripts/grant_dev_access.sh richardjoy9946@gmail.com
#
# Run as the project owner (quantumduobuilder@gmail.com).
set -euo pipefail

PROJECT_ID="project-f0fb8de7-7240-4128-965"
DEV_EMAIL="${1:-}"

[[ -z "$DEV_EMAIL" ]] && { echo "Usage: $0 richardjoy9946@gmail.com"; exit 1; }

echo "Granting $DEV_EMAIL access to project $PROJECT_ID ..."

# Core roles needed for local dev
ROLES=(
  "roles/run.developer"           # Cloud Run — view logs, describe services
  "roles/bigquery.dataEditor"     # BigQuery — read/write analytics tables
  "roles/bigquery.jobUser"        # BigQuery — run queries
  "roles/storage.objectAdmin"     # GCS — upload/download media
  "roles/pubsub.editor"           # Pub/Sub — publish + subscribe
  "roles/cloudsql.client"         # Cloud SQL — connect via proxy
  "roles/secretmanager.secretAccessor"  # Secret Manager — read secrets
  "roles/logging.viewer"          # Cloud Logging — read logs
  "roles/monitoring.viewer"       # Cloud Monitoring — read metrics
  "roles/cloudbuild.builds.editor" # Cloud Build — submit builds
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="user:${DEV_EMAIL}" \
    --role="$ROLE" \
    --quiet
  echo "  ✓ $ROLE"
done

echo ""
echo "✅  Done. $DEV_EMAIL can now run:  ./dev-setup.sh"
