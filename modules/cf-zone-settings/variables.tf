variable "zone_id" {
  description = "Cloudflare Zone ID to apply settings to."
  type        = string
}

# ─── TLS / HTTPS ──────────────────────────────────────────────────────────────

variable "ssl" {
  description = "SSL/TLS encryption mode. Use 'full_strict' for origin cert validation."
  type        = string
  default     = "full_strict"
}

variable "min_tls_version" {
  description = "Minimum TLS version accepted by the zone."
  type        = string
  default     = "1.2"
}

variable "tls_1_3" {
  description = "Enable TLS 1.3 support."
  type        = string
  default     = "on"
}

variable "always_use_https" {
  description = "Redirect all HTTP requests to HTTPS."
  type        = string
  default     = "on"
}

variable "automatic_https_rewrites" {
  description = "Automatically rewrite HTTP URLs in content to HTTPS."
  type        = string
  default     = "on"
}

variable "opportunistic_encryption" {
  description = "Advertise HTTP/2 support over HTTP connections."
  type        = string
  default     = "on"
}

# ─── PERFORMANCE ──────────────────────────────────────────────────────────────

variable "zero_rtt" {
  description = "Enable 0-RTT connection resumption (CF setting id: 0rtt)."
  type        = string
  default     = "on"
}

variable "http3" {
  description = "Enable HTTP/3 (QUIC) support."
  type        = string
  default     = "on"
}

variable "brotli" {
  description = "Enable Brotli compression for supported content types."
  type        = string
  default     = "on"
}

# ─── PRIVACY / IP ─────────────────────────────────────────────────────────────

variable "ip_geolocation" {
  description = "Add CF-IPCountry header to all requests."
  type        = string
  default     = "on"
}

variable "true_client_ip_header" {
  description = "Add True-Client-IP header. Off for API deployments to avoid header spoofing risk."
  type        = string
  default     = "off"
}

# ─── OBFUSCATION / INJECTION (off for API/JSON deployments) ───────────────────

variable "email_obfuscation" {
  description = "Obfuscate email addresses in HTML. Off: API returns JSON, not HTML."
  type        = string
  default     = "off"
}

variable "rocket_loader" {
  description = "Async-load JS via Rocket Loader. Off: breaks SPAs and Workers-served JSON."
  type        = string
  default     = "off"
}

variable "server_side_exclude" {
  description = "Hide specific HTML content from bots via <!--sse--> tags."
  type        = string
  default     = "off"
}

variable "hotlink_protection" {
  description = "Block direct linking to zone assets from external sites."
  type        = string
  default     = "off"
}

# ─── SECURITY ─────────────────────────────────────────────────────────────────

variable "security_level" {
  description = "WAF threat score threshold. Values: essentially_off, low, medium, high, under_attack."
  type        = string
  default     = "medium"
}

variable "browser_check" {
  description = "Challenge requests from browsers with suspicious user-agent strings."
  type        = string
  default     = "on"
}

variable "challenge_ttl" {
  description = "Seconds a passed challenge is remembered. Range: 300–31536000."
  type        = number
  default     = 1800
}

variable "websockets" {
  description = "Allow WebSocket connections through the zone."
  type        = string
  default     = "on"
}

# ─── DEVELOPMENT MODE ─────────────────────────────────────────────────────────

variable "development_mode" {
  description = "Bypass cache for all requests. On only during active debugging."
  type        = string
  default     = "off"
}

# ─── HSTS (security_header) ───────────────────────────────────────────────────

variable "security_header" {
  description = "HSTS configuration applied via the security_header zone setting."
  type = object({
    enabled            = bool
    max_age            = number
    include_subdomains = bool
    preload            = bool
    nosniff            = bool
  })
  default = {
    enabled            = true
    max_age            = 15552000 # 180 days
    include_subdomains = true
    preload            = false
    nosniff            = true
  }
}
