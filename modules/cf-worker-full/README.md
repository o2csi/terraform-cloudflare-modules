# cf-worker-full

Creates a `cloudflare_workers_script` in the supplied `account_id` with `worker_name`, `placeholder_content`, runtime compatibility settings, and bindings assembled from the binding variables. The module requires `zone_id` even when no route is created.

An empty `route_pattern` skips the `cloudflare_workers_route`, and an empty `cron_triggers` list skips the `cloudflare_workers_cron_trigger`. The script lifecycle ignores later changes to `content`, compatibility settings, and bindings; a supplied service binding names the Worker script assigned to that binding. A precondition on the script resource refuses duplicate binding names, as soon as the value is known, during plan for literal inputs or during apply for values that depend on other resources, across every binding category and names every duplicate.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "worker" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-worker-full?ref=v0.3.0"

  account_id         = "0123456789abcdef0123456789abcdef"
  worker_name        = "example-worker"
  zone_id            = "fedcba9876543210fedcba9876543210"
  compatibility_date = "2026-01-01"
  route_pattern      = "api.example.invalid/*"
}
```
