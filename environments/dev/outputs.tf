output "network_name" {
  description = "Name of the VPC network"
  value       = module.networking.network_name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = module.networking.subnet_name
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "database_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = module.database.connection_name
}

output "database_private_ip" {
  description = "Cloud SQL private IP address"
  value       = module.database.private_ip
  sensitive   = true
}

output "gke_service_account_email" {
  description = "GKE node service account email"
  value       = module.iam.gke_service_account_email
}

output "app_service_account_email" {
  description = "Application workload service account email"
  value       = module.iam.app_service_account_email
}
