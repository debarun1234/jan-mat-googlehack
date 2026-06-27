#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  JanMat — Owner / CI Infrastructure Setup
#  Run ONCE by the project owner to create all GCP resources.
#  Your partner/co-developer should run dev-setup.sh instead.
#
#  Usage:  ./setup.sh
#  Prereqs: gcloud CLI authed as quantumduobuilder@gmail.com,
#           terraform >= 1.5, python3
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Config (edit these if project ever changes) ──────────────────────
PROJECT_ID="project-f0fb8de7-7240-4128-965"
ACCOUNT="quantumduobuilder@gmail.com"
REGION="asia-south1"
INSTANCE_NAME="janmat-db-poc"
TFDIR="infra/terraform"

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ── Prerequisites ────────────────────────────────────────────────────
step "Checking prerequisites"
command -v gcloud    >/dev/null || err "gcloud CLI not found → https://cloud.google.com/sdk/docs/install"
command -v terraform >/dev/null || err "terraform not found → https://developer.hashicorp.com/terraform/downloads"
command -v python3   >/dev/null || err "python3 not found"
log "gcloud   : $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null | head -1)"
log "terraform: $(terraform version -json | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])')"

# ── gcloud auth ──────────────────────────────────────────────────────
step "Configuring gcloud"
gcloud config set project  "$PROJECT_ID" --quiet
gcloud config set account  "$ACCOUNT"    --quiet

# Ensure ADC is set (no quota-project warning)
if ! gcloud auth application-default print-access-token &>/dev/null; then
  warn "ADC not logged in — opening browser..."
  gcloud auth application-default login --quiet
fi
gcloud auth application-default set-quota-project "$PROJECT_ID" --quiet
log "ADC quota project → $PROJECT_ID"

# ── Enable ALL required APIs (idempotent — safe to re-run) ───────────
step "Enabling GCP APIs (this may take 2–3 min on first run)"
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  pubsub.googleapis.com \
  speech.googleapis.com \
  translate.googleapis.com \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  identitytoolkit.googleapis.com \
  maps-backend.googleapis.com \
  --project="$PROJECT_ID" --quiet
log "All APIs enabled"

# ── DB password ──────────────────────────────────────────────────────
step "DB password"
if [[ ! -f ".db_password" ]]; then
  DB_PASSWORD=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(32)))")
  echo "$DB_PASSWORD" > .db_password
  chmod 600 .db_password
  log "Generated → .db_password  (git-ignored; back it up!)"
else
  DB_PASSWORD=$(cat .db_password)
  log "Using existing .db_password"
fi

# ── terraform.tfvars ─────────────────────────────────────────────────
step "Creating terraform.tfvars"
cat > "$TFDIR/terraform.tfvars" <<EOF
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
zone         = "${REGION}-a"
environment  = "poc"

db_password  = "${DB_PASSWORD}"
db_name      = "janmat"
db_user      = "janmat_user"

# 11:00 PM IST = 17:30 UTC  |  7:00 AM IST = 01:30 UTC
db_stop_schedule  = "30 17 * * *"
db_start_schedule = "30 1 * * *"

gemini_model    = "gemini-2.5-flash-lite"
constituency_id = "KA-BLR-NORTH-01"
EOF
log "terraform.tfvars written"

# ── Terraform ────────────────────────────────────────────────────────
step "Terraform init + apply  (~8–12 min)"
cd "$TFDIR"
terraform init -upgrade
terraform plan -out=tfplan
echo ""
warn "This will CREATE GCP resources and incur costs (~\$14/month)."
read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
terraform apply tfplan
log "Terraform complete"
cd ../..

# ── Secret Manager — populate secrets ────────────────────────────────
step "Populating Secret Manager"

# JWT secret (auto-generated)
JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
echo -n "$JWT_SECRET" | gcloud secrets versions add janmat-jwt-secret \
  --project="$PROJECT_ID" --data-file=- --quiet
log "JWT secret → Secret Manager"

# Maps API key
echo ""
warn "Google Maps API key needed (Maps JS + Geocoding APIs enabled on it)."
warn "Create at: https://console.cloud.google.com/apis/credentials"
read -rp "Maps API key (Enter to skip): " MAPS_KEY
if [[ -n "$MAPS_KEY" ]]; then
  echo -n "$MAPS_KEY" | gcloud secrets versions add janmat-maps-api-key \
    --project="$PROJECT_ID" --data-file=- --quiet
  log "Maps key → Secret Manager"
else
  warn "Skipped — add later: echo -n 'KEY' | gcloud secrets versions add janmat-maps-api-key --data-file=-"
fi

# Google OAuth credentials (for MP Dashboard)
echo ""
warn "Google OAuth 2.0 client needed for MP Dashboard login."
warn "Create at: https://console.cloud.google.com/apis/credentials → OAuth 2.0 Client ID (Web)"
warn "Callback URL: http://localhost:3000/auth/google/callback  (add prod URL too when deploying)"
read -rp "Google Client ID     : " GOOGLE_CLIENT_ID
read -rp "Google Client Secret : " GOOGLE_CLIENT_SECRET
if [[ -n "$GOOGLE_CLIENT_ID" && -n "$GOOGLE_CLIENT_SECRET" ]]; then
  echo -n "$GOOGLE_CLIENT_ID"     | gcloud secrets versions add janmat-google-client-id     --project="$PROJECT_ID" --data-file=- --quiet
  echo -n "$GOOGLE_CLIENT_SECRET" | gcloud secrets versions add janmat-google-client-secret --project="$PROJECT_ID" --data-file=- --quiet
  log "OAuth credentials → Secret Manager"
else
  warn "Skipped — MP Dashboard Google login won't work until these are set"
fi

# ── Wait for Cloud SQL ───────────────────────────────────────────────
step "Waiting for Cloud SQL to be RUNNABLE"
sleep 30
for i in {1..12}; do
  STATUS=$(gcloud sql instances describe "$INSTANCE_NAME" \
    --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || echo "PENDING")
  [[ "$STATUS" == "RUNNABLE" ]] && { log "Cloud SQL ready"; break; }
  echo "  ($i/12) $STATUS — waiting 15s..."
  sleep 15
done

# ── DB schema ────────────────────────────────────────────────────────
step "Applying Cloud SQL schema"
if command -v cloud-sql-proxy >/dev/null; then
  chmod +x infra/scripts/db_init.sh
  DB_PASSWORD_ARG="$DB_PASSWORD" ./infra/scripts/db_init.sh "$PROJECT_ID"
  log "Schema applied"
else
  warn "cloud-sql-proxy not installed — apply schema manually:"
  warn "  brew install cloud-sql-proxy    # or download binary"
  warn "  ./infra/scripts/db_init.sh $PROJECT_ID"
fi

# ── Seed BigQuery ────────────────────────────────────────────────────
step "Seeding BigQuery (Census / NFHS mock data)"
pip3 install google-cloud-bigquery --quiet --break-system-packages 2>/dev/null || \
  pip3 install google-cloud-bigquery --quiet
python3 infra/scripts/seed_bigquery.py --project "$PROJECT_ID"
log "BigQuery seeded"

# ── Grant partner access (optional) ─────────────────────────────────
step "Partner access"
warn "To grant your co-developer access, run the IAM grant section in dev-setup.sh"
warn "OR run:  ./infra/scripts/grant_dev_access.sh PARTNER_EMAIL"

# ── Build + deploy backend ───────────────────────────────────────────
step "Building & deploying backend to Cloud Run"
gcloud builds submit \
  --tag "gcr.io/${PROJECT_ID}/janmat-backend" \
  --dockerfile backend/Dockerfile \
  --project "$PROJECT_ID" \
  .
gcloud run services update janmat-backend \
  --image "gcr.io/${PROJECT_ID}/janmat-backend:latest" \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --quiet
log "Backend deployed"

# ── Summary ──────────────────────────────────────────────────────────
step "✅  Setup complete"
BACKEND_URL=$(cd "$TFDIR" && terraform output -raw cloud_run_url 2>/dev/null || echo "(run: terraform output cloud_run_url)")

echo ""
echo -e "${GREEN}${BOLD}JanMat is live!${NC}"
printf "  %-20s %s\n" "Project:"     "$PROJECT_ID"
printf "  %-20s %s\n" "Region:"      "$REGION"
printf "  %-20s %s\n" "Backend URL:" "$BACKEND_URL"
printf "  %-20s %s\n" "DB:"          "$INSTANCE_NAME  (auto-stop 11PM / start 7AM IST)"
echo ""
echo -e "${YELLOW}Share with your partner:${NC}"
echo "  1. git clone <repo>"
echo "  2. ./dev-setup.sh"
echo ""
echo -e "${RED}⚠  Never commit:${NC}  .db_password  |  terraform.tfvars  |  .env files"
