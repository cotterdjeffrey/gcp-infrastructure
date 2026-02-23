output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_id" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_id" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.subnet.id
}

output "pods_range_name" {
  description = "Name of the secondary range for GKE pods"
  value       = "pods"
}

output "services_range_name" {
  description = "Name of the secondary range for GKE services"
  value       = "services"
}

output "private_services_connection" {
  description = "Private services connection for Cloud SQL"
  value       = google_service_networking_connection.private_services.id
}
