output "id" {
  description = "D1 database UUID (used for worker bindings)."
  value       = cloudflare_d1_database.this.id
}

output "name" {
  description = "D1 database name."
  value       = cloudflare_d1_database.this.name
}
