# cf-hyperdrive

Creates a `cloudflare_hyperdrive_config` in the supplied `account_id` and configures caching from `caching_enabled`, `caching_max_age`, and `caching_stale_while_revalidate`. `origin_database_url` is split by the regular expression in `main.tf`: its accepted scheme is `postgresql` or `postgres` and is normalized to `postgres`; the five captured fields are passed to the origin unchanged. A `validation` in `variables.tf` refuses at plan a value outside `postgresql://<user>:<password>@<host>:<port>/<database>`: user and database are non-empty and contain none of `: @ / ? # %`; password is non-empty and contains none of `@ ? # %` (so `:` and `/` are allowed); host is a non-empty run of characters outside `: @ / ? # % [ ]` (so no bracketed IPv6 literal, and no check that it is a resolvable name); port has one to five digits. Nothing is percent-decoded and no query string or fragment is separated, so a password containing `@ ? # %` cannot be passed through this input; a `/` in the database part is also refused.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "hyperdrive" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-hyperdrive?ref=v0.3.0"

  account_id          = "0123456789abcdef0123456789abcdef"
  name                = "example-hyperdrive"
  origin_database_url = "postgresql://example_user:example_password@db.example.invalid:5432/example_database"
}
```
