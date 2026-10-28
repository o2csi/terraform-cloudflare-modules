# cf-access-app

Creates a `cloudflare_zero_trust_access_application` in the supplied `account_id` for `domain`. The module creates a `cloudflare_zero_trust_access_policy` when `allowed_emails` or `allowed_email_domains` is non-empty, and attaches it with `policy_precedence`. A user must match any listed exact email address OR email domain.

`allowed_email_domains` defaults to `[]` and accepts bare domains such as `example.com`, up to 253 characters with labels up to 63 characters. Wildcards, email addresses, URLs, paths, and whitespace are rejected.

`required_login_method_id` defaults to `null`. Set it to an existing identity provider ID to require that login method AND a matching email address or domain. The module adds it to the policy's `require` rules.

`allowed_idps` selects the identity providers offered by the application; it does not add a policy login-method requirement. The module does not create identity providers. When both email lists are empty, the application has no allow policy, even if either identity provider setting is supplied.

When a generated allow policy uses `required_login_method_id`, a non-empty
`allowed_idps` list must include that provider. The application may offer other
providers while the policy requires one of them. An empty list keeps all
configured providers available; `null` leaves the application setting unset.

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

For a domain policy, set `allowed_email_domains = ["example.com"]`. Set
`allowed_idps` to the identity provider offered at login and
`required_login_method_id` to the provider that must authenticate the user.

Set `extra_policy_ids` to existing reusable Access policy IDs when the application
also needs another authorization method, such as a CI service token policy with
`decision = "non_identity"`. The default `[]` adds nothing. The module preserves
the generated email/domain policy and its required login method. Additional
policies receive consecutive precedences starting at `policy_precedence + 1`,
including when no human policy is generated. IDs must be distinct, non-empty and
have no surrounding whitespace. The caller owns each reusable policy's rules.
