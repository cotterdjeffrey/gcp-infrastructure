# Budget alert — prevent surprise bills by capping spend with email notifications
data "google_billing_account" "account" {
  billing_account = var.billing_account_id
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account_id
  display_name    = "${var.environment}-monthly-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.monthly_limit
    }
  }

  # Alert at 50%, 80%, and 100% of budget
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
}
