output "budget_name" {
  description = "Name of the billing budget"
  value       = google_billing_budget.monthly.display_name
}
