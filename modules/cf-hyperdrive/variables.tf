variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "name" {
  description = "Display name for the Hyperdrive configuration (e.g. \"example-hyperdrive-prod\")."
  type        = string
}

variable "origin_database_url" {
  description = "Full PostgreSQL connection URL for the origin database. It accepts postgresql://<user>:<password>@<host>:<port>/<database> or postgres://<user>:<password>@<host>:<port>/<database>; user and database cannot contain : @ / ? # %, password cannot contain @ ? # %, host cannot contain : @ / ? # % [ ], and port has 1 to 5 digits and is between 1 and 65535."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(?:postgresql|postgres)://[^:@/?#%]+:[^@?#%]+@[^:@/?#%\\[\\]]+:[0-9]{1,5}/[^/?#%@]+$", var.origin_database_url))
    error_message = "origin_database_url must be postgresql://<user>:<password>@<host>:<port>/<database> where user and database contain none of : @ / ? # %, the password contains none of @ ? # %, the host contains none of : @ / ? # % [ ] (so no bracketed IPv6 literal), and the port is 1 to 5 digits. Nothing is percent-decoded and no query string or fragment is separated, so a password containing @ ? # or % cannot be passed through this input."
  }

  validation {
    condition     = alltrue([for p in regexall("^[a-z]+://[^@]+@[^:/]+:([0-9]+)/", var.origin_database_url) : tonumber(p[0]) >= 1 && tonumber(p[0]) <= 65535])
    error_message = "The origin port must be between 1 and 65535."
  }
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
