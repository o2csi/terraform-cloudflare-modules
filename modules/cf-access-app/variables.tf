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
  description = "Email addresses allowed by the generated allow policy. Empty list disables the policy."
  type        = list(string)
  default     = []
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
