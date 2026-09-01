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
