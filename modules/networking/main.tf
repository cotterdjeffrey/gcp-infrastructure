# VPC — custom mode so we control all subnets explicitly
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-${var.vpc_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Primary subnet with secondary ranges for GKE pods and services
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-${var.vpc_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

# Allow internal communication between all resources in the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

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

  source_ranges = [var.subnet_cidr]

  description = "Allow all internal traffic within the VPC subnet"
}

# Allow GCP health check probes to reach load-balanced services
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.environment}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  # Google health check IP ranges (documented by GCP)
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  description = "Allow GCP load balancer health check probes"
}

# Deny all other ingress — defense in depth on top of GCP's implied deny
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.environment}-deny-all-ingress"
  project  = var.project_id
  network  = google_compute_network.vpc.id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  description = "Explicit deny-all ingress as defense in depth"
}

# Reserve an IP range for private services (Cloud SQL, Memorystore, etc.)
resource "google_compute_global_address" "private_services_ip" {
  name          = "${var.environment}-private-services-ip"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Private service connection — lets Cloud SQL use private IPs in our VPC
resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_ip.name]
}
