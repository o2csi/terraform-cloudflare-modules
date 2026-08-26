variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "name" {
  description = "Display name for the Hyperdrive configuration (e.g. \"example-hyperdrive-prod\")."
  type        = string
}

variable "origin_database_url" {
  description = "Full PostgreSQL connection URL for the origin database. Format: postgresql://<user>:<password>@<host>:<port>/<database>"
  type        = string
  sensitive   = true
}

variable "caching_enabled" {
  description = "Whether Hyperdrive query caching is enabled."
  type        = bool
  default     = true
}

variable "caching_max_age" {
  description = "Maximum age in seconds for cached query results."
  type        = number
  default     = 60
}

variable "caching_stale_while_revalidate" {
  description = "Stale-while-revalidate window in seconds for cached query results."
  type        = number
  default     = 15
}
