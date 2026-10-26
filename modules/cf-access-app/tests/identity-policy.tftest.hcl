mock_provider "cloudflare" {}

variables {
  account_id = "0123456789abcdef0123456789abcdef"
  app_name   = "example-access"
  domain     = "admin.example.invalid"
}

run "defaults_create_no_allow_policy" {
  command = plan

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.this) == 0 && length(cloudflare_zero_trust_access_application.this.policies) == 0
    error_message = "Empty email inputs must leave the application without an allow policy."
  }
}

run "legacy_exact_emails_are_preserved" {
  command = plan

  variables {
    allowed_emails    = ["admin@example.invalid", "support@example.invalid"]
    policy_precedence = 7
  }

  assert {
    condition = (
      length(cloudflare_zero_trust_access_policy.this) == 1 &&
      cloudflare_zero_trust_access_policy.this[0].decision == "allow" &&
      length(cloudflare_zero_trust_access_policy.this[0].include) == 2 &&
      toset([for rule in cloudflare_zero_trust_access_policy.this[0].include : rule.email.email]) == toset(var.allowed_emails) &&
      alltrue([for rule in cloudflare_zero_trust_access_policy.this[0].include : rule.email_domain == null && rule.login_method == null]) &&
      length(cloudflare_zero_trust_access_policy.this[0].require) == 0 &&
      length(cloudflare_zero_trust_access_application.this.policies) == 1 &&
      one(cloudflare_zero_trust_access_application.this.policies).precedence == 7
    )
    error_message = "Exact-email callers must retain their email selectors, precedence, and absence of login-method requirements."
  }
}

run "domain_only_creates_email_domain_selector" {
  command = plan

  variables {
    allowed_email_domains = ["o2csi.com"]
  }

  assert {
    condition = (
      length(cloudflare_zero_trust_access_policy.this) == 1 &&
      one(cloudflare_zero_trust_access_policy.this[0].include).email_domain.domain == "o2csi.com" &&
      one(cloudflare_zero_trust_access_policy.this[0].include).email == null &&
      length(cloudflare_zero_trust_access_policy.this[0].require) == 0 &&
      length(cloudflare_zero_trust_access_application.this.policies) == 1
    )
    error_message = "A domain-only caller must create and attach one allow policy containing the email-domain selector."
  }
}

run "emails_and_domains_share_or_include_rules" {
  command = plan

  variables {
    allowed_emails        = ["admin@example.invalid"]
    allowed_email_domains = ["o2csi.com", "sub.example.invalid"]
  }

  assert {
    condition = (
      length(cloudflare_zero_trust_access_policy.this[0].include) == 3 &&
      toset(compact([for rule in cloudflare_zero_trust_access_policy.this[0].include : try(rule.email.email, null)])) == toset(var.allowed_emails) &&
      toset(compact([for rule in cloudflare_zero_trust_access_policy.this[0].include : try(rule.email_domain.domain, null)])) == toset(var.allowed_email_domains) &&
      length(cloudflare_zero_trust_access_policy.this[0].require) == 0
    )
    error_message = "Each email address and domain must remain an alternative in include, with no additional require rule."
  }
}

run "required_identity_provider_is_an_and_requirement" {
  command = plan

  variables {
    allowed_email_domains     = ["o2csi.com"]
    allowed_idps              = ["11111111-2222-3333-4444-555555555555"]
    required_login_method_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    auto_redirect_to_identity = true
  }

  assert {
    condition = (
      one(cloudflare_zero_trust_access_policy.this[0].require).login_method.id == var.required_login_method_id &&
      one(cloudflare_zero_trust_access_policy.this[0].require).email_domain == null &&
      one(cloudflare_zero_trust_access_policy.this[0].include).email_domain.domain == "o2csi.com" &&
      one(cloudflare_zero_trust_access_policy.this[0].include).login_method == null &&
      toset(cloudflare_zero_trust_access_application.this.allowed_idps) == toset(var.allowed_idps) &&
      cloudflare_zero_trust_access_application.this.auto_redirect_to_identity
    )
    error_message = "The explicit required IdP must be in require; allowed_idps and redirect settings must remain application settings."
  }
}

run "application_idps_do_not_add_policy_requirements" {
  command = plan

  variables {
    allowed_emails           = ["admin@example.invalid"]
    allowed_idps             = ["11111111-2222-3333-4444-555555555555"]
    required_login_method_id = null
  }

  assert {
    condition = (
      length(cloudflare_zero_trust_access_policy.this[0].require) == 0 &&
      one(cloudflare_zero_trust_access_policy.this[0].include).email.email == "admin@example.invalid" &&
      toset(cloudflare_zero_trust_access_application.this.allowed_idps) == toset(var.allowed_idps)
    )
    error_message = "A null required_login_method_id must not infer a policy requirement from allowed_idps."
  }
}

run "identity_provider_only_creates_no_allow_policy" {
  command = plan

  variables {
    allowed_idps             = ["11111111-2222-3333-4444-555555555555"]
    required_login_method_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.this) == 0 && length(cloudflare_zero_trust_access_application.this.policies) == 0
    error_message = "Identity provider settings alone must not create an allow policy."
  }
}

run "rejects_wildcard_domain" {
  command = plan
  variables { allowed_email_domains = ["*.example.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_email_address_as_domain" {
  command = plan
  variables { allowed_email_domains = ["admin@example.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_url_as_domain" {
  command = plan
  variables { allowed_email_domains = ["https://example.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_domain_path" {
  command = plan
  variables { allowed_email_domains = ["example.com/admin"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_domain_whitespace" {
  command = plan
  variables { allowed_email_domains = [" example.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_internal_domain_whitespace" {
  command = plan
  variables { allowed_email_domains = ["exam ple.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_empty_domain" {
  command = plan
  variables { allowed_email_domains = [""] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_empty_domain_label" {
  command = plan
  variables { allowed_email_domains = ["example..com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_empty_required_identity_provider" {
  command = plan
  variables { required_login_method_id = "" }
  expect_failures = [var.required_login_method_id]
}

run "accepts_63_character_domain_label" {
  command = plan

  variables {
    allowed_email_domains = ["${join("", [for i in range(63) : "a"])}.com"]
  }

  assert {
    condition     = one(cloudflare_zero_trust_access_policy.this[0].include).email_domain.domain == one(var.allowed_email_domains)
    error_message = "A 63-character label must remain a valid email-domain selector."
  }
}

run "accepts_253_character_domain" {
  command = plan

  variables {
    allowed_email_domains = [join(".", [for size in [63, 63, 63, 61] : join("", [for i in range(size) : "a"])])]
  }

  assert {
    condition     = one(cloudflare_zero_trust_access_policy.this[0].include).email_domain.domain == one(var.allowed_email_domains)
    error_message = "A 253-character domain with valid labels must remain a valid email-domain selector."
  }
}

run "rejects_64_character_domain_label" {
  command = plan
  variables { allowed_email_domains = ["${join("", [for i in range(64) : "a"])}.com"] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_254_character_domain" {
  command = plan
  variables { allowed_email_domains = [join(".", [for size in [63, 63, 63, 62] : join("", [for i in range(size) : "a"])])] }
  expect_failures = [var.allowed_email_domains]
}

run "rejects_blank_required_identity_provider" {
  command = plan
  variables { required_login_method_id = "   " }
  expect_failures = [var.required_login_method_id]
}
