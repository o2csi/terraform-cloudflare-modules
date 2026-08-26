output "id" {
  description = "DNS record ID."
  value       = cloudflare_dns_record.this.id
}

output "name" {
  description = "DNS record name."
  value       = cloudflare_dns_record.this.name
}

output "content" {
  description = "DNS record content (value)."
  value       = cloudflare_dns_record.this.content
}
