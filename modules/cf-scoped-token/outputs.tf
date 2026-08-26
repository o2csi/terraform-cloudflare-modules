output "id" {
  description = "The ID of the created API token."
  value       = cloudflare_api_token.this.id
}

output "value" {
  description = "The secret value of the created API token. Treat as sensitive."
  value       = cloudflare_api_token.this.value
  sensitive   = true
}
