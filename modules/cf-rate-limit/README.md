# cf-rate-limit

Creates a zone-scoped `cloudflare_ruleset` in the `http_ratelimit` phase for the supplied `zone_id`. Each object in `rules` becomes an enabled rule with its `action`, response, rate-limit values, expression, and description.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "rate_limit" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-rate-limit?ref=v0.2.0"

  zone_id      = "0123456789abcdef0123456789abcdef"
  ruleset_name = "example-rate-limit"
  rules = [
    {
      description = "Limit example API requests"
      expression  = "http.request.uri.path starts_with \"/api/\""
      ratelimit = {
        characteristics     = ["ip.src"]
        period              = 60
        requests_per_period = 100
      }
    }
  ]
}
```
