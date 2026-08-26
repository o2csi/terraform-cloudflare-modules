output "script_name" {
  description = "The name of the deployed Worker script."
  value       = cloudflare_workers_script.this.script_name
}

output "script_id" {
  description = "The Terraform resource ID of the Worker script."
  value       = cloudflare_workers_script.this.id
}

output "route_id" {
  description = "The ID of the Workers route, or null if no route was created."
  value       = length(cloudflare_workers_route.this) > 0 ? cloudflare_workers_route.this[0].id : null
}
