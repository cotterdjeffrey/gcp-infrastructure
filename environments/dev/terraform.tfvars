project_id  = "cotter-cloud-dev"
region      = "us-central1"
environment = "dev"

# Billing account ID and secrets — pass these via CI/CD variables or a .tfvars
# file excluded from version control. Never commit real values.
billing_account_id     = "REPLACE_WITH_BILLING_ACCOUNT_ID"
db_password            = "CHANGE_ME_use_ci_variable"
grafana_admin_password = "CHANGE_ME_use_ci_variable"
anthropic_api_key      = "CHANGE_ME_use_ci_variable"
