output "db_password_secret_id" {
  description = "Secret Manager resource ID for the database password"
  value       = google_secret_manager_secret.db_password.id
}

output "grafana_admin_password_secret_id" {
  description = "Secret Manager resource ID for the Grafana admin password"
  value       = google_secret_manager_secret.grafana_admin_password.id
}
