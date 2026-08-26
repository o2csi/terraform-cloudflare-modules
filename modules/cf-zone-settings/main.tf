# Module: cf-zone-settings
# Applies zone-level hardening settings for an edge deployment.
# One cloudflare_zone_setting resource per setting (CF provider v5 model).
# No outputs — pure side-effect module.

# ─── TLS / HTTPS ──────────────────────────────────────────────────────────────

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = var.ssl
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}

resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = var.zone_id
  setting_id = "tls_1_3"
  value      = var.tls_1_3
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = var.always_use_https
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  zone_id    = var.zone_id
  setting_id = "automatic_https_rewrites"
  value      = var.automatic_https_rewrites
}

resource "cloudflare_zone_setting" "opportunistic_encryption" {
  zone_id    = var.zone_id
  setting_id = "opportunistic_encryption"
  value      = var.opportunistic_encryption
}

# ─── PERFORMANCE ──────────────────────────────────────────────────────────────

# Note: variable is named zero_rtt for HCL validity; setting_id is "0rtt" per CF API.
resource "cloudflare_zone_setting" "zero_rtt" {
  zone_id    = var.zone_id
  setting_id = "0rtt"
  value      = var.zero_rtt
}

resource "cloudflare_zone_setting" "http3" {
  zone_id    = var.zone_id
  setting_id = "http3"
  value      = var.http3
}

resource "cloudflare_zone_setting" "brotli" {
  zone_id    = var.zone_id
  setting_id = "brotli"
  value      = var.brotli
}

# ─── PRIVACY / IP ─────────────────────────────────────────────────────────────

resource "cloudflare_zone_setting" "ip_geolocation" {
  zone_id    = var.zone_id
  setting_id = "ip_geolocation"
  value      = var.ip_geolocation
}

resource "cloudflare_zone_setting" "true_client_ip_header" {
  zone_id    = var.zone_id
  setting_id = "true_client_ip_header"
  value      = var.true_client_ip_header
}

# ─── OBFUSCATION / INJECTION ──────────────────────────────────────────────────

resource "cloudflare_zone_setting" "email_obfuscation" {
  zone_id    = var.zone_id
  setting_id = "email_obfuscation"
  value      = var.email_obfuscation
}

resource "cloudflare_zone_setting" "rocket_loader" {
  zone_id    = var.zone_id
  setting_id = "rocket_loader"
  value      = var.rocket_loader
}

resource "cloudflare_zone_setting" "server_side_exclude" {
  zone_id    = var.zone_id
  setting_id = "server_side_exclude"
  value      = var.server_side_exclude
}

resource "cloudflare_zone_setting" "hotlink_protection" {
  zone_id    = var.zone_id
  setting_id = "hotlink_protection"
  value      = var.hotlink_protection
}

# ─── SECURITY ─────────────────────────────────────────────────────────────────

resource "cloudflare_zone_setting" "security_level" {
  zone_id    = var.zone_id
  setting_id = "security_level"
  value      = var.security_level
}

resource "cloudflare_zone_setting" "browser_check" {
  zone_id    = var.zone_id
  setting_id = "browser_check"
  value      = var.browser_check
}

resource "cloudflare_zone_setting" "challenge_ttl" {
  zone_id    = var.zone_id
  setting_id = "challenge_ttl"
  value      = var.challenge_ttl
}

resource "cloudflare_zone_setting" "websockets" {
  zone_id    = var.zone_id
  setting_id = "websockets"
  value      = var.websockets
}

# ─── DEVELOPMENT MODE ─────────────────────────────────────────────────────────

resource "cloudflare_zone_setting" "development_mode" {
  zone_id    = var.zone_id
  setting_id = "development_mode"
  value      = var.development_mode
}

# ─── HSTS (security_header) ───────────────────────────────────────────────────
# CF v5 schema: value is an object with a strict_transport_security nested object.
# See: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_setting

resource "cloudflare_zone_setting" "security_header" {
  zone_id    = var.zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = var.security_header.enabled
      max_age            = var.security_header.max_age
      include_subdomains = var.security_header.include_subdomains
      preload            = var.security_header.preload
      nosniff            = var.security_header.nosniff
    }
  }
}
