variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "title" {
  description = "KV namespace title (unique within the account; user-facing name)."
  type        = string
}
