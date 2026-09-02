# cf-zone-settings

Applies 21 `cloudflare_zone_setting` resources to the supplied `zone_id`. The resources use the setting variables for TLS, HTTPS, performance, privacy, obfuscation, security, development mode, and `security_header` values.

The `zero_rtt` resource uses `setting_id = "0rtt"`, and the `security_header` resource nests the `security_header` variable in `strict_transport_security`. The module returns no outputs, so a consumer expresses required ordering with `depends_on`.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "zone_settings" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-zone-settings?ref=v0.3.0"

  zone_id = "0123456789abcdef0123456789abcdef"
}
```
