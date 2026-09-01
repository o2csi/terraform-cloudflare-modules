# cf-dns-record

Creates one `cloudflare_dns_record` in the supplied `zone_id`, using `name`, `type`, and `content`. The `ttl`, `proxied`, `priority`, `comment`, and `tags` variables are passed directly to that record.

The default `ttl` is `1` and the default `proxied` value is `true`; callers can set either variable explicitly.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "dns_record" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-dns-record?ref=v0.2.0"

  zone_id = "0123456789abcdef0123456789abcdef"
  name    = "api.example.invalid"
  type    = "A"
  content = "192.0.2.10"
}
```
