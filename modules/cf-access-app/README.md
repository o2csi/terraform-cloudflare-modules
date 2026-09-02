# cf-access-app

Creates a `cloudflare_zero_trust_access_application` in the supplied `account_id` for `domain`. The optional allow policy is a `cloudflare_zero_trust_access_policy` created only when `allowed_emails` is non-empty, and the application attaches that policy with `policy_precedence`.

`allowed_idps` lists identity provider IDs from the account's Zero Trust configuration; the module does not create them. An empty `allowed_emails` list leaves the application with an empty `policies` list.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "access_app" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-access-app?ref=v0.3.0"

  account_id     = "0123456789abcdef0123456789abcdef"
  app_name       = "example-admin"
  domain         = "admin.example.invalid"
  allowed_emails = ["admin@example.invalid"]
}
```
