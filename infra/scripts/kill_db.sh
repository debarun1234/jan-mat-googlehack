#!/usr/bin/env bash
# kill_db.sh — Manually stop Cloud SQL to save credits
# Usage: ./infra/scripts/kill_db.sh YOUR_PROJECT_ID

set -euo pipefail
PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then echo "Usage: $0 <project-id>"; exit 1; fi

INSTANCE="janmat-db-poc"
echo "🛑 Stopping Cloud SQL instance: $INSTANCE"
gcloud sql instances patch "$INSTANCE" \
  --project="$PROJECT_ID" \
  --activation-policy=NEVER \
  --quiet
echo "✅ DB stopped. Credits saved."
