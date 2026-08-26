# Thin wrapper around cloudflare_api_token for generating sub-scoped tokens
# (e.g. for wrangler deploy CI pipelines).
#
# The CF provider v5 schema for cloudflare_api_token:
#   - policies.permission_groups = list of objects { id = string }
#   - policies.resources         = jsonencode(map(string))
#
# The caller passes plain map(string) for resources; this module applies
# jsonencode() so the caller never has to.

resource "cloudflare_api_token" "this" {
  name = var.name

  policies = [
    for p in var.policies : {
      effect = p.effect
      permission_groups = [
        for gid in p.permission_groups : { id = gid }
      ]
      resources = jsonencode(p.resources)
    }
  ]
}
