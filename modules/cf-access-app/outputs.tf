output "app_id" {
  description = "ID of the Zero Trust Access application."
  value       = cloudflare_zero_trust_access_application.this.id
}

output "policy_id" {
  description = "ID of the generated allow policy, or null if no emails configured."
  value       = length(cloudflare_zero_trust_access_policy.this) > 0 ? cloudflare_zero_trust_access_policy.this[0].id : null
}
