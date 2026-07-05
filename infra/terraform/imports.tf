# ─────────────────────────────────────────────────────────────────────────────
# Declarative import blocks (Terraform 1.7+)
# These are IDEMPOTENT — if a resource is already in state, the block is a no-op.
# Leave them here permanently; they never hurt and protect against state drift.
# ─────────────────────────────────────────────────────────────────────────────

# ── BigQuery tables ──────────────────────────────────────────────────────────

import {
  to = google_bigquery_table.citizen_grievances
  id = "projects/${var.project_id}/datasets/janmat_analytics/tables/citizen_grievances"
}

import {
  to = google_bigquery_table.demand_hotspots
  id = "projects/${var.project_id}/datasets/janmat_analytics/tables/demand_hotspots"
}

import {
  to = google_bigquery_table.priority_scores
  id = "projects/${var.project_id}/datasets/janmat_analytics/tables/priority_scores"
}

import {
  to = google_bigquery_table.public_infrastructure
  id = "projects/${var.project_id}/datasets/janmat_infrastructure/tables/public_infrastructure"
}

# ── Networking ───────────────────────────────────────────────────────────────

import {
  to = google_compute_subnetwork.janmat_subnet
  id = "projects/${var.project_id}/regions/asia-south1/subnetworks/janmat-subnet"
}

import {
  to = google_compute_global_address.private_ip_range
  id = "projects/${var.project_id}/global/addresses/janmat-private-ip-range"
}

import {
  to = google_vpc_access_connector.janmat_connector
  id = "projects/${var.project_id}/locations/asia-south1/connectors/janmat-connector"
}

import {
  to = google_compute_firewall.allow_internal
  id = "projects/${var.project_id}/global/firewalls/janmat-allow-internal"
}

import {
  to = google_compute_firewall.deny_ingress
  id = "projects/${var.project_id}/global/firewalls/janmat-deny-ingress"
}

# ── Pub/Sub subscriptions ────────────────────────────────────────────────────

import {
  to = google_pubsub_subscription.grievance_processor
  id = "projects/${var.project_id}/subscriptions/grievance-processor-sub"
}

import {
  to = google_pubsub_subscription.analytics_trigger
  id = "projects/${var.project_id}/subscriptions/analytics-trigger-sub"
}

import {
  to = google_pubsub_subscription.dashboard_refresh
  id = "projects/${var.project_id}/subscriptions/dashboard-refresh-sub"
}

import {
  to = google_pubsub_subscription.grievance_dlq_sub
  id = "projects/${var.project_id}/subscriptions/grievance-dlq-sub"
}
