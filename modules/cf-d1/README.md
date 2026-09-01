# cf-d1

Creates a `cloudflare_d1_database` named by `name` in the supplied `account_id`. The optional `primary_location_hint` is passed to the database resource.

The resource has `lifecycle.ignore_changes = [read_replication]`, so Cloudflare-managed read-replication changes are not reconciled by this module.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "d1" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-d1?ref=v0.2.0"

  account_id            = "0123456789abcdef0123456789abcdef"
  name                  = "example-database"
  primary_location_hint = "weur"
}
```
