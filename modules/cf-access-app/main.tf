locals {
  policy_enabled = length(var.allowed_emails) > 0
}

# Allow policy (only created when allowed_emails is non-empty).
# Created BEFORE the app so it can be referenced in app.policies.
resource "cloudflare_zero_trust_access_policy" "this" {
  count = local.policy_enabled ? 1 : 0

  account_id = var.account_id
  name       = "${var.app_name}-allow"
  decision   = "allow"

  include = [
    for email in var.allowed_emails : {
      email = { email = email }
    }
  ]
}

# Zero Trust Access application.
# In CF provider v5, policies are attached via the `policies` attribute on the
# application (not via a separate application_id on the policy resource).
resource "cloudflare_zero_trust_access_application" "this" {
  account_id                = var.account_id
  name                      = var.app_name
  domain                    = var.domain
  type                      = var.app_type
  session_duration          = var.session_duration
  allowed_idps              = var.allowed_idps
  auto_redirect_to_identity = var.auto_redirect_to_identity

  policies = local.policy_enabled ? [
    {
      id         = cloudflare_zero_trust_access_policy.this[0].id
      precedence = var.policy_precedence
    },
  ] : []
}
