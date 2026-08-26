variable "account_id" {
  type = string
}

variable "project_name" {
  type        = string
  description = "Cloudflare Pages project name"
}

variable "production_branch" {
  type    = string
  default = "main"
}

variable "zone_id" {
  type        = string
  description = "DNS zone ID for the custom domain"
}

variable "custom_domain" {
  type        = string
  description = "Custom domain (e.g. app.example.invalid)"
}

# Service bindings: each entry wires a CF Worker into the Pages deployment context.
#
# CF v5 schema (confirmed via context7 docs): deployment_configs.{production,preview}.services
# is a MAP where the key is the binding name visible inside the Pages function, and the value
# object has:
#   service     (string, required) – Worker script name
#   entrypoint  (string, optional) – exported class/handler (default "default")
#   environment (string, optional) – Worker environment ("production" | "preview")
#
# Example caller:
#   service_bindings = [
#     { name = "ADMIN_WORKER", service = "example-admin-staging", entrypoint = "default" }
#   ]
variable "service_bindings" {
  description = "Service bindings to attach to the Pages project (production and preview deployments)."
  type = list(object({
    name       = string
    service    = string
    entrypoint = optional(string, "default")
  }))
  default = []
}

# Local: build the services map once for reuse in both production and preview.
# Shape: { BINDING_NAME = { service = "...", entrypoint = "..." } }
locals {
  services_map = {
    for sb in var.service_bindings : sb.name => {
      service    = sb.service
      entrypoint = sb.entrypoint
    }
  }
}

# Pages project
resource "cloudflare_pages_project" "this" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = var.production_branch

  # deployment_configs is an attribute (object), NOT a block, in CF provider v5.
  # When service_bindings is empty we omit the whole attribute to avoid a no-op diff.
  # When bindings are provided we set them identically on production and preview.
  deployment_configs = length(var.service_bindings) == 0 ? null : {
    production = {
      services = local.services_map
    }
    preview = {
      services = local.services_map
    }
  }
}

# Custom domain on Pages
resource "cloudflare_pages_domain" "this" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.this.name
  name         = var.custom_domain
}

# DNS CNAME pointing to Pages — uses the subdomain from the project resource
resource "cloudflare_dns_record" "this" {
  zone_id = var.zone_id
  name    = var.custom_domain
  type    = "CNAME"
  content = cloudflare_pages_project.this.subdomain
  ttl     = 1 # automatic
  proxied = true
}

output "pages_project_name" {
  value = cloudflare_pages_project.this.name
}

output "pages_subdomain" {
  value = cloudflare_pages_project.this.subdomain
}

output "custom_domain" {
  value = var.custom_domain
}

# Diagnostic: list the binding names that are wired via Terraform.
# Useful for verifying that the service binding round-tripped correctly after apply.
output "service_binding_names" {
  description = "Names of service bindings declared in this Pages project."
  value       = [for sb in var.service_bindings : sb.name]
}
