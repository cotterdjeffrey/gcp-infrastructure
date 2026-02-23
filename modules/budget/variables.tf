variable "project_id" {
  description = "GCP project ID to monitor"
  type        = string
}

variable "billing_account_id" {
  description = "GCP billing account ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "monthly_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 10
}
