# cf-scoped-token

Creates a `cloudflare_api_token` with the supplied `name` and `policies`. Each policy converts its `resources` map with `jsonencode` and converts every `permission_groups` ID into the provider's object form.

The module returns the token `id` and its sensitive `value`.

```hcl
# This configuration uses illustrative values. Replace them before applying.
module "scoped_token" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-scoped-token?ref=v0.2.0"

  name = "example-deploy-token"
  policies = [
    {
      effect               = "allow"
      permission_groups    = ["0123456789abcdef0123456789abcdef"]
      resources = {
        "com.cloudflare.api.account.0123456789abcdef0123456789abcdef" = "*"
      }
    }
  ]
}
```
