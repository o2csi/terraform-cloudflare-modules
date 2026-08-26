variable "zone_id" {
  description = "Cloudflare zone ID where the record lives."
  type        = string
}

variable "name" {
  description = "DNS record name (e.g. \"api.example.invalid\" or \"@\" for apex)."
  type        = string
}

variable "type" {
  description = "DNS record type (A, AAAA, CNAME, TXT, MX, SRV, CAA, NS, etc.)."
  type        = string
}

variable "content" {
  description = "Record content (IP for A/AAAA, hostname for CNAME, text for TXT, etc.)."
  type        = string
}

variable "ttl" {
  description = "TTL in seconds, or 1 for \"automatic\" (required when proxied = true)."
  type        = number
  default     = 1
}

variable "proxied" {
  description = "Whether the record is proxied through Cloudflare (orange cloud). Only valid for A, AAAA, CNAME."
  type        = bool
  default     = true
}

variable "priority" {
  description = "Record priority (required for MX, optional for SRV/URI). Null to omit."
  type        = number
  default     = null
}

variable "comment" {
  description = "Optional human-readable comment shown in the CF dashboard."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional list of tags for filtering in the CF dashboard."
  type        = list(string)
  default     = null
}
