project_id         = "cotter-cloud-dev"
region             = "us-central1"
environment        = "dev"
billing_account_id = "0175A8-0C88ED-6CD49D"

# Secrets — in production, pass these via CI/CD variables or a .tfvars file
# excluded from version control. Never commit real credentials.
db_password            = "CHANGE_ME_use_ci_variable"
grafana_admin_password = "CHANGE_ME_use_ci_variable"
