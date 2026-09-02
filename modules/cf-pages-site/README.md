# cf-pages-site

Creates a `cloudflare_pages_project`, a `cloudflare_pages_domain`, and a `cloudflare_dns_record` for `custom_domain`. The supplied `account_id` owns the Pages resources, and `zone_id` identifies the existing DNS zone for the CNAME.

The CNAME always has `type = "CNAME"`, `ttl = 1`, and `proxied = true`. When `service_bindings` is non-empty, the project sets the same service map for both production and preview deployments; each binding's `service` names a Worker script in the same account, which the module does not create. A `validation` on `service_bindings` refuses duplicate binding names at plan and names each duplicate.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "pages_site" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-pages-site?ref=v0.3.0"

  account_id   = "0123456789abcdef0123456789abcdef"
  project_name = "example-pages-site"
  zone_id      = "fedcba9876543210fedcba9876543210"
  custom_domain = "app.example.invalid"

  service_bindings = [
    {
      name       = "EXAMPLE_SERVICE"
      service    = "example-worker"
      entrypoint = "default"
    }
  ]
}
```
