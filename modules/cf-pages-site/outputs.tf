output "pages_project_name" {
  description = "Name of the created Cloudflare Pages project."
  value       = cloudflare_pages_project.this.name
}

output "pages_subdomain" {
  description = "Cloudflare Pages subdomain assigned to the created project."
  value       = cloudflare_pages_project.this.subdomain
}

output "custom_domain" {
  description = "Custom domain configured for the Pages project and DNS CNAME."
  value       = var.custom_domain
}

# Declared service binding names.
output "service_binding_names" {
  description = "Names of service bindings declared in this Pages project."
  value       = [for sb in var.service_bindings : sb.name]
}
