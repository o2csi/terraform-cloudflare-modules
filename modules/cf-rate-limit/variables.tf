variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID to attach the rate-limit ruleset to."
}

variable "ruleset_name" {
  type        = string
  description = "Display name of the ruleset (e.g. \"Example rate limiting\")."
}

variable "rules" {
  type = list(object({
    description = string
    expression  = string
    action      = optional(string, "block")
    ratelimit = object({
      characteristics     = list(string)
      period              = number
      requests_per_period = number
      mitigation_timeout  = optional(number, 60)
    })
    response = optional(object({
      status_code  = number
      content_type = string
      content      = string
      }), {
      status_code  = 429
      content_type = "application/json"
      content      = "{\"error\":\"rate_limited\"}\n"
    })
  }))
  description = "List of rate-limit rules to add to the ruleset."
}
