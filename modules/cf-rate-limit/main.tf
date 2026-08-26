# Zone-level rate-limit ruleset (phase http_ratelimit).
# Uses the Cloudflare provider's zone-level rate-limiting ruleset schema:
#   action / action_parameters.response / ratelimit / expression / description / enabled

resource "cloudflare_ruleset" "this" {
  zone_id = var.zone_id
  name    = var.ruleset_name
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    for r in var.rules : {
      action = r.action
      action_parameters = {
        response = {
          status_code  = r.response.status_code
          content_type = r.response.content_type
          content      = r.response.content
        }
      }
      ratelimit = {
        characteristics     = r.ratelimit.characteristics
        period              = r.ratelimit.period
        requests_per_period = r.ratelimit.requests_per_period
        mitigation_timeout  = r.ratelimit.mitigation_timeout
      }
      expression  = r.expression
      description = r.description
      enabled     = true
    }
  ]
}
