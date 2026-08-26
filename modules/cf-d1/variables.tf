variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "name" {
  description = "D1 database name (unique within the account)."
  type        = string
}

variable "primary_location_hint" {
  description = "Optional hint for the D1 primary region (e.g. \"wnam\", \"enam\", \"weur\", \"eeur\", \"apac\", \"oc\"). Null = auto."
  type        = string
  default     = null
}
