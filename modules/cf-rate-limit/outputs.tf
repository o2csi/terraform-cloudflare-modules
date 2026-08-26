output "ruleset_id" {
  description = "The ID of the created rate-limit ruleset."
  value       = cloudflare_ruleset.this.id
}
