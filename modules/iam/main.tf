# Dedicated service account for GKE nodes
# Using a custom SA instead of the default compute SA enforces least privilege
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.environment}-gke-nodes"
  display_name = "GKE Node Service Account (${var.environment})"
  project      = var.project_id
}

# GKE nodes need to pull container images
resource "google_project_iam_member" "gke_nodes_gcr" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# GKE nodes need to write logs
resource "google_project_iam_member" "gke_nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# GKE nodes need to export metrics
resource "google_project_iam_member" "gke_nodes_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Dedicated service account for the application workload
# Tied to a K8s service account via Workload Identity
resource "google_service_account" "app_workload" {
  account_id   = "${var.environment}-app-workload"
  display_name = "App Workload Service Account (${var.environment})"
  project      = var.project_id
}

# App workload needs Cloud SQL client access to connect to Postgres
resource "google_project_iam_member" "app_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app_workload.email}"
}

# Allow GKE to impersonate the app SA via Workload Identity.
# Binds the app-workload KSA in the "app" namespace (k8s/app/serviceaccount.yaml)
# to this GCP service account.
resource "google_service_account_iam_member" "app_workload_identity" {
  service_account_id = google_service_account.app_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[app/app-workload]"
}

# Dedicated service account for Grafana, so it can read its admin password from
# Secret Manager via Workload Identity (same pattern as the app workload).
resource "google_service_account" "grafana" {
  account_id   = "${var.environment}-grafana"
  display_name = "Grafana Service Account (${var.environment})"
  project      = var.project_id
}

# Binds the grafana KSA in the "monitoring" namespace
# (k8s/monitoring/grafana/serviceaccount.yaml) to this GCP service account.
resource "google_service_account_iam_member" "grafana_workload_identity" {
  service_account_id = google_service_account.grafana.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/grafana]"
}
