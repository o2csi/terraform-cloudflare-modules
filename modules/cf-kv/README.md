# cf-kv

Creates a `cloudflare_workers_kv_namespace` with `title` in the supplied `account_id`. The module returns the namespace `id` and `title`.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "kv" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-kv?ref=v0.3.0"

  account_id = "0123456789abcdef0123456789abcdef"
  title      = "example-namespace"
}
```
