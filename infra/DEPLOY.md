# JanMat — Infrastructure Deployment Guide

## Prerequisites

```bash
# Install tools
brew install terraform google-cloud-sdk
gcloud components install cloud-sql-proxy

# Auth
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

## Deploy Order

### Step 1 — Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id and db_password

terraform init
terraform plan
terraform apply
```

Terraform will:
- Enable all required GCP APIs (~5 min)
- Create VPC + private service connection
- Create Cloud SQL PostgreSQL (db-f1-micro, private IP)
- Create BigQuery datasets + tables
- Create GCS media bucket (with 30-day lifecycle)
- Create 3 Pub/Sub topics + subscriptions + DLQ
- Create service accounts + IAM bindings
- Create Secret Manager secrets (empty placeholders)
- Create Cloud Scheduler jobs for DB kill/restart
- Create Cloud Run service (placeholder image)

### Step 2 — Populate Secrets

```bash
# Maps API key (get from Google Cloud Console → APIs & Services → Credentials)
echo -n "YOUR_MAPS_API_KEY" | gcloud secrets versions add janmat-maps-api-key --data-file=-

# JWT secret (generate random)
openssl rand -hex 32 | gcloud secrets versions add janmat-jwt-secret --data-file=-
```

### Step 3 — Initialize Cloud SQL Schema

```bash
chmod +x infra/scripts/db_init.sh
./infra/scripts/db_init.sh YOUR_PROJECT_ID
```

### Step 4 — Seed BigQuery Infrastructure Data

```bash
pip install google-cloud-bigquery
python infra/scripts/seed_bigquery.py --project YOUR_PROJECT_ID
```

### Step 5 — Build & Deploy Backend

```bash
# Build Docker image and push to GCR
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/janmat-backend:latest ./backend

# Update Cloud Run to use the new image
gcloud run services update janmat-backend \
  --image gcr.io/YOUR_PROJECT_ID/janmat-backend:latest \
  --region asia-south1
```

---

## Cost Control

### Automated (via Cloud Scheduler)
- **11:00 PM IST** → DB stopped automatically
- **7:00 AM IST** → DB started automatically
- Cloud Run scales to zero when no requests

### Manual Override

```bash
# Stop DB immediately (e.g., end of dev session)
./infra/scripts/kill_db.sh YOUR_PROJECT_ID

# Start DB when needed
./infra/scripts/start_db.sh YOUR_PROJECT_ID

# Trigger scheduler job manually (for testing)
gcloud scheduler jobs run janmat-stop-db --location=asia-south1
gcloud scheduler jobs run janmat-start-db --location=asia-south1
```

### Estimated Monthly Cost (POC, light usage)

| Resource              | Cost/month  |
|-----------------------|-------------|
| Cloud SQL f1-micro    | ~$4–7       |
| Cloud Run (requests)  | ~$0–3       |
| BigQuery (queries)    | ~$0 (free tier) |
| Cloud Storage         | ~$0.50      |
| Gemini Flash tokens   | ~$3–10      |
| Speech-to-Text        | ~$0–2       |
| Translation API       | ~$0–2       |
| Pub/Sub               | ~$0 (free tier) |
| **Total**             | **~$10–25** |

Budget remaining from $300: **$275–290** 🟢

---

## Teardown

```bash
cd infra/terraform
terraform destroy
```

This deletes everything. BigQuery datasets have `delete_contents_on_destroy = true`
so all data will be lost. Cloud SQL `deletion_protection = false` allows destroy.
