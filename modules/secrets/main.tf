# Secret Manager — centralized secrets with IAM-based access control.
# Replaces hardcoded passwords in Terraform and Kubernetes manifests.
# Pairs with Workload Identity: pods authenticate as GCP service accounts
# to read secrets without managing keys.

# Database password secret
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.environment}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# Grafana admin password secret
resource "google_secret_manager_secret" "grafana_admin_password" {
  project   = var.project_id
  secret_id = "${var.environment}-grafana-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "grafana_admin_password" {
  secret      = google_secret_manager_secret.grafana_admin_password.id
  secret_data = var.grafana_admin_password
}

# Grant the application service account access to the database password.
# With Workload Identity, the K8s service account maps to this GCP service account,
# so the pod can read the secret without a key file.
resource "google_secret_manager_secret_iam_member" "app_db_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_account_email}"
}
