# GKE Autopilot cluster — Google manages node pools, scaling, and OS patching
# Autopilot is simpler than Standard and cost-optimized (pay per pod, not per node)
resource "google_container_cluster" "autopilot" {
  name     = "${var.environment}-autopilot-cluster"
  project  = var.project_id
  location = var.region

  # Autopilot mode — no manual node pool configuration needed
  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  # Use the secondary ranges we defined in the networking module
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster — nodes get internal IPs only, reducing attack surface
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Workload Identity ties K8s service accounts to GCP service accounts
  # This eliminates the need for exported service account keys
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Use the dedicated node service account instead of default compute SA
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = var.gke_service_account_email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  # Release channel keeps the cluster auto-updated with stable patches
  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false
}
