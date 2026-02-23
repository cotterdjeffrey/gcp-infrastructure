# Remote state configuration using GCS
# This demonstrates knowledge of remote state best practices.
# For portfolio validation we use local state (no terraform apply),
# but production would use this GCS backend.

# terraform {
#   backend "gcs" {
#     bucket = "cotter-cloud-dev-tfstate"
#     prefix = "env/dev"
#   }
# }
