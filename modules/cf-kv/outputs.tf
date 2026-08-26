output "id" {
  description = "KV namespace ID (used for worker bindings)."
  value       = cloudflare_workers_kv_namespace.this.id
}

output "title" {
  description = "KV namespace title."
  value       = cloudflare_workers_kv_namespace.this.title
}
