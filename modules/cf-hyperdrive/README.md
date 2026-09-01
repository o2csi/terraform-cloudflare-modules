# cf-hyperdrive

Creates a `cloudflare_hyperdrive_config` in the supplied `account_id` and configures caching from `caching_enabled`, `caching_max_age`, and `caching_stale_while_revalidate`. It splits `origin_database_url` with the regular expression in `main.tf` and passes each part to the origin unchanged: the scheme is `postgresql` or `postgres`, the user contains no `:`, the password no `@`, the host no `:` (so no IPv6 literal), the port is digits, and everything after the first `/` is taken as the database name. Nothing is percent-decoded and a query string is not separated; a password containing `@`, `/` or `%` cannot be passed through this input.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "hyperdrive" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-hyperdrive?ref=v0.2.0"

  account_id          = "0123456789abcdef0123456789abcdef"
  name                = "example-hyperdrive"
  origin_database_url = "postgresql://example_user:example_password@db.example.invalid:5432/example_database"
}
```
