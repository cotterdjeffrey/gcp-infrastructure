# Cloud SQL Postgres instance — managed database with automated backups and patching
resource "google_sql_database_instance" "postgres" {
  name             = "${var.environment}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  # Ensure the private services connection is created before the instance
  depends_on = [var.private_services_connection]

  settings {
    tier              = var.tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    # Private IP only — no public access reduces attack surface
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }
  }

  deletion_protection = false
}

# Application database
resource "google_sql_database" "app" {
  name     = "app"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
}

# Database user for the application
resource "google_sql_user" "app" {
  name     = "app"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  password = "changeme-use-secret-manager-in-production"
}
