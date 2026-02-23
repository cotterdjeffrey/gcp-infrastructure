module "networking" {
  source = "../../modules/networking"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
}

module "iam" {
  source = "../../modules/iam"

  project_id  = var.project_id
  environment = var.environment
}

module "gke" {
  source = "../../modules/gke"

  project_id                = var.project_id
  region                    = var.region
  environment               = var.environment
  network_id                = module.networking.network_id
  subnet_id                 = module.networking.subnet_id
  pods_range_name           = module.networking.pods_range_name
  services_range_name       = module.networking.services_range_name
  gke_service_account_email = module.iam.gke_service_account_email
}

module "database" {
  source = "../../modules/database"

  project_id                  = var.project_id
  region                      = var.region
  environment                 = var.environment
  network_id                  = module.networking.network_id
  private_services_connection = module.networking.private_services_connection
}
