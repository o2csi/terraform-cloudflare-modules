output "id" {
  description = "The ID of the Hyperdrive configuration. Pass this to cf-worker-full as a hyperdrive_bindings value."
  value       = cloudflare_hyperdrive_config.this.id
}

output "name" {
  description = "The display name of the Hyperdrive configuration."
  value       = cloudflare_hyperdrive_config.this.name
}
