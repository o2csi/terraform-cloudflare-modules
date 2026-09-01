# cf-hyperdrive

Creates a `cloudflare_hyperdrive_config` in the supplied `account_id`. It parses `origin_database_url` into the PostgreSQL origin fields and configures caching from `caching_enabled`, `caching_max_age`, and `caching_stale_while_revalidate`.

The database URL must match the `postgresql://user:password@host:port/database` or `postgres://user:password@host:port/database` expression used by `regex`.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "hyperdrive" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-hyperdrive?ref=v0.2.0"

  account_id          = "0123456789abcdef0123456789abcdef"
  name                = "example-hyperdrive"
  origin_database_url = "postgresql://example_user:example_password@db.example.invalid:5432/example_database"
}
```
