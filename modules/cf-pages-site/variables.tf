variable "account_id" {
  description = "Cloudflare account ID that owns the Pages project."
  type        = string
}

variable "project_name" {
  type        = string
  description = "Cloudflare Pages project name"
}

variable "production_branch" {
  description = "Git branch used for production Pages deployments."
  type        = string
  default     = "main"
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

  validation {
    condition     = length(var.service_bindings[*].name) == length(distinct(var.service_bindings[*].name))
    error_message = "Service binding names must be unique: ${jsonencode([for n in distinct(var.service_bindings[*].name) : n if length([for m in var.service_bindings[*].name : m if m == n]) > 1])}."
  }
}
