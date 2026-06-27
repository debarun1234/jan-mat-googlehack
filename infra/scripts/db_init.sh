#!/usr/bin/env bash
# db_init.sh — Apply Cloud SQL schema after Terraform deploy
# Usage: ./infra/scripts/db_init.sh YOUR_PROJECT_ID

set -euo pipefail

PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 <project-id>"
  exit 1
fi

INSTANCE_NAME="janmat-db-poc"
DB_NAME="janmat"
DB_USER="janmat_user"
REGION="asia-south1"

echo "🔐 Fetching DB password from Secret Manager..."
DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="janmat-db-url" \
  --project="$PROJECT_ID" \
  | python3 -c "import sys; url=sys.stdin.read().strip(); print(url.split(':')[2].split('@')[0])")

echo "📦 Applying schema via Cloud SQL proxy..."

# Start Cloud SQL Auth Proxy in background
cloud-sql-proxy "${PROJECT_ID}:${REGION}:${INSTANCE_NAME}" \
  --port=5433 \
  --quiet &
PROXY_PID=$!

sleep 3

PGPASSWORD="$DB_PASSWORD" psql \
  -h 127.0.0.1 \
  -p 5433 \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -f "infra/sql/001_init_schema.sql"

echo "✅ Schema applied successfully"

kill $PROXY_PID
echo "✅ Proxy stopped"
