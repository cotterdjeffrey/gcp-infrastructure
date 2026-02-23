output "gke_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_nodes.email
}

output "app_service_account_email" {
  description = "Email of the app workload service account"
  value       = google_service_account.app_workload.email
}
