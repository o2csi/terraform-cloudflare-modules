variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "app_name" {
  description = "Access application display name."
  type        = string
}

variable "domain" {
  description = "Domain to protect. May include a path (e.g. \"sub.example.invalid/admin\")."
  type        = string
}

variable "allowed_emails" {
  description = "Email addresses allowed by the generated allow policy. The policy is disabled when both email lists are empty."
  type        = list(string)
  default     = []
}

variable "allowed_email_domains" {
  description = "Bare email domains allowed by the generated allow policy (e.g. example.com). Matches any listed email address OR domain."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for domain in var.allowed_email_domains :
      try(
        can(regex("^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", domain)) &&
        length(domain) <= 253 &&
        alltrue([for label in split(".", domain) : length(label) <= 63]),
        false,
      )
    ])
    error_message = "allowed_email_domains must contain bare domains such as example.com, at most 253 characters with labels at most 63 characters, without wildcards, @, URLs, paths, or whitespace."
  }
}

variable "required_login_method_id" {
  description = "Identity provider ID required in addition to a matching email address or domain. Null adds no login-method requirement."
  type        = string
  default     = null

  validation {
    condition     = var.required_login_method_id == null ? true : trimspace(var.required_login_method_id) != ""
    error_message = "required_login_method_id must be null or a non-empty identity provider ID."
  }
}

variable "allowed_idps" {
  description = "List of Identity Provider IDs allowed on this app (e.g. Google Workspace IdP ID). Empty list = all configured IdPs."
  type        = list(string)
  default     = []
}

variable "auto_redirect_to_identity" {
  description = "If true, automatically redirect to the configured IdP (skips the Access picker screen)."
  type        = bool
  default     = false
}

variable "session_duration" {
  description = "How long a user's session lasts before re-auth."
  type        = string
  default     = "24h"
}

variable "app_type" {
  description = "Access application type. Usually \"self_hosted\" for web apps."
  type        = string
  default     = "self_hosted"
}

variable "policy_precedence" {
  description = "Precedence of the generated policy on the app (lower = evaluated first)."
  type        = number
  default     = 1
}

variable "extra_policy_ids" {
  description = "Existing reusable Access policy IDs to attach after the generated human allow policy, starting at policy_precedence + 1. Empty leaves existing callers unchanged."
  type        = list(string)
  default     = []

  validation {
    condition = (
      alltrue([for id in var.extra_policy_ids : trimspace(id) != "" && id == trimspace(id)]) &&
      length(distinct(var.extra_policy_ids)) == length(var.extra_policy_ids)
    )
    error_message = "extra_policy_ids must contain distinct non-empty IDs without surrounding whitespace."
  }
}
