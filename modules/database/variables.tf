variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "VPC network self-link"
  type        = string
}

variable "private_services_connection" {
  description = "Private services connection ID (ensures dependency ordering)"
  type        = string
}

variable "database_version" {
  description = "Cloud SQL Postgres version"
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine tier for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
}
