# cf-access-app

Creates a `cloudflare_zero_trust_access_application` in the supplied `account_id` for `domain`. The module creates a `cloudflare_zero_trust_access_policy` when `allowed_emails` or `allowed_email_domains` is non-empty, and attaches it with `policy_precedence`. A user must match any listed exact email address OR email domain.

`allowed_email_domains` defaults to `[]` and accepts bare domains such as `example.com`, up to 253 characters with labels up to 63 characters. Wildcards, email addresses, URLs, paths, and whitespace are rejected.

`required_login_method_id` defaults to `null`. Set it to an existing identity provider ID to require that login method AND a matching email address or domain. The module adds it to the policy's `require` rules.

`allowed_idps` selects the identity providers offered by the application; it does not add a policy login-method requirement. The module does not create identity providers. When both email lists are empty, the application has no allow policy, even if either identity provider setting is supplied.

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

To allow an email domain through one required identity provider:

```hcl
allowed_email_domains    = ["example.com"]
allowed_idps             = ["01234567-89ab-cdef-0123-456789abcdef"]
required_login_method_id = "01234567-89ab-cdef-0123-456789abcdef"
```
