variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "worker_name" {
  description = "Name of the Worker script (also used as the script_name)."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID for the route (required even if no route is created)."
  type        = string
}

variable "route_pattern" {
  description = "URL pattern for the Workers route. Empty string disables route creation."
  type        = string
  default     = ""
}

variable "compatibility_date" {
  description = "Compatibility date for the Worker runtime."
  type        = string
}

variable "compatibility_flags" {
  description = "List of compatibility flags for the Worker runtime."
  type        = list(string)
  default     = ["nodejs_compat"]
}

variable "kv_bindings" {
  description = "Map of KV namespace bindings: { binding_name = namespace_id }."
  type        = map(string)
  default     = {}
}

variable "durable_object_bindings" {
  description = "List of Durable Object namespace bindings."
  type = list(object({
    name        = string
    class_name  = string
    script_name = optional(string) # null = same script
  }))
  default = []
}

variable "do_migrations" {
  description = "Durable Object migrations descriptor (single object, v5 schema). Pass null to omit migrations entirely."
  type = object({
    tag         = string
    new_classes = optional(list(string))
    transferred_classes = optional(list(object({
      from        = string
      from_script = string
      to          = string
    })))
    deleted_classes = optional(list(string))
    renamed_classes = optional(list(object({
      from = string
      to   = string
    })))
  })
  default = null
}

variable "d1_bindings" {
  description = "Map of D1 database bindings: { BINDING_NAME = database_id }. Optional; empty = no D1 bindings (backward compatible)."
  type        = map(string)
  default     = {}
}

variable "hyperdrive_bindings" {
  description = "Map of Hyperdrive bindings: { binding_name = hyperdrive_config_id }."
  type        = map(string)
  default     = {}
}

variable "service_bindings" {
  description = "List of service bindings (Worker-to-Worker)."
  type = list(object({
    name       = string
    service    = string
    entrypoint = optional(string, "default")
  }))
  default = []
}

variable "secret_names" {
  description = "List of secret binding names. Values are set out-of-band via `wrangler secret put`."
  type        = list(string)
  default     = []
}

variable "cron_triggers" {
  description = "List of cron schedule expressions (e.g. [\"*/30 * * * *\"]). Empty list disables the trigger resource."
  type        = list(string)
  default     = []
}

variable "plain_vars" {
  description = "Map of plain-text environment variable bindings: { var_name = value }."
  type        = map(string)
  default     = {}
}

variable "placeholder_content" {
  description = "Placeholder Worker JS content deployed on first apply. Subsequent wrangler deploys update the real content; Terraform ignores content drift via lifecycle."
  type        = string
  default     = "export default { fetch() { return new Response('ok') } }"
}
