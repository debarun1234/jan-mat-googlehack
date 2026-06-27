#!/usr/bin/env bash
# start_db.sh — Manually start Cloud SQL
# Usage: ./infra/scripts/start_db.sh YOUR_PROJECT_ID

set -euo pipefail
PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then echo "Usage: $0 <project-id>"; exit 1; fi

INSTANCE="janmat-db-poc"
echo "▶️  Starting Cloud SQL instance: $INSTANCE"
gcloud sql instances patch "$INSTANCE" \
  --project="$PROJECT_ID" \
  --activation-policy=ALWAYS \
  --quiet
echo "✅ DB started. Ready in ~30 seconds."
