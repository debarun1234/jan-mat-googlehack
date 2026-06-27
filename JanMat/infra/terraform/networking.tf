# ─────────────────────────────────────────
# VPC Network
# ─────────────────────────────────────────
resource "google_compute_network" "janmat_vpc" {
  name                    = "janmat-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

# Primary subnet for Cloud Run VPC connector
resource "google_compute_subnetwork" "janmat_subnet" {
  name          = "janmat-subnet"
  ip_cidr_range = "10.8.0.0/24"
  region        = var.region
  network       = google_compute_network.janmat_vpc.id

  private_ip_google_access = true # Allow private access to Google APIs
}

# ─────────────────────────────────────────
# Private Service Connection (for Cloud SQL private IP)
# ─────────────────────────────────────────
resource "google_compute_global_address" "private_ip_range" {
  name          = "janmat-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.janmat_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.janmat_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.apis]
}

# ─────────────────────────────────────────
# Serverless VPC Access Connector
# Allows Cloud Run to reach Cloud SQL on private IP
# ─────────────────────────────────────────
resource "google_vpc_access_connector" "janmat_connector" {
  name          = "janmat-vpc-connector"
  region        = var.region
  network       = google_compute_network.janmat_vpc.name
  ip_cidr_range = "10.9.0.0/28" # /28 required for connector

  # min/max throughput — keep min low for cost (200 = 1 instance)
  min_throughput = 200
  max_throughput = 300

  depends_on = [google_project_service.apis]
}

# ─────────────────────────────────────────
# Firewall Rules
# ─────────────────────────────────────────

# Allow internal traffic within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "janmat-allow-internal"
  network = google_compute_network.janmat_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.8.0.0/24", "10.9.0.0/28"]
}

# Block all other ingress by default (Cloud Run is internet-facing via managed LB)
resource "google_compute_firewall" "deny_ingress" {
  name     = "janmat-deny-ingress"
  network  = google_compute_network.janmat_vpc.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"

  # Exclude the internal ranges above
  target_tags = ["janmat-internal-only"]
}
