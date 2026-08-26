locals {
  # Build a flat bindings list by concatenating all binding types.
  # CF provider v5 uses a unified `bindings` list of objects (not separate block types).

  kv_bindings = [
    for name, id in var.kv_bindings : {
      name         = name
      type         = "kv_namespace"
      namespace_id = id
    }
  ]

  do_bindings = [
    for b in var.durable_object_bindings : {
      name        = b.name
      type        = "durable_object_namespace"
      class_name  = b.class_name
      script_name = b.script_name
    }
  ]

  d1_bindings = [
    for name, id in var.d1_bindings : {
      name = name
      type = "d1"
      id   = id
    }
  ]

  hyperdrive_bindings = [
    for name, id in var.hyperdrive_bindings : {
      name = name
      type = "hyperdrive"
      id   = id
    }
  ]

  service_bindings = [
    for b in var.service_bindings : {
      name       = b.name
      type       = "service"
      service    = b.service
      entrypoint = b.entrypoint
    }
  ]

  # Secret bindings: type = "secret_text" with no value attribute.
  # The actual secret value is set out-of-band via `wrangler secret put`.
  # Terraform registers the binding slot; wrangler populates it.
  secret_bindings = [
    for n in var.secret_names : {
      name = n
      type = "secret_text"
    }
  ]

  plain_text_bindings = [
    for k, v in var.plain_vars : {
      name = k
      type = "plain_text"
      text = v
    }
  ]

  all_bindings = concat(
    local.kv_bindings,
    local.do_bindings,
    local.d1_bindings,
    local.hyperdrive_bindings,
    local.service_bindings,
    local.secret_bindings,
    local.plain_text_bindings,
  )

  # Migrations: CF provider v5 uses a single `migrations` object (not a list).
  # Schema: { old_tag, new_tag, new_classes, deleted_classes, renamed_classes, transferred_classes, steps }
  # The variable uses `tag` as the new_tag; old_tag is omitted (first migration or use steps for sequences).
  #
  # ASSUMPTION: `migrations` is a single nested object, not a list.
  # If the provider errors with "expected list", wrap in a list: migrations = [{ ... }]
  migrations = var.do_migrations == null ? null : {
    new_tag             = var.do_migrations.tag
    new_classes         = var.do_migrations.new_classes
    deleted_classes     = var.do_migrations.deleted_classes
    renamed_classes     = var.do_migrations.renamed_classes
    transferred_classes = var.do_migrations.transferred_classes
  }
}

resource "cloudflare_workers_script" "this" {
  account_id  = var.account_id
  script_name = var.worker_name
  content     = var.placeholder_content
  main_module = "index.js"

  compatibility_date  = var.compatibility_date
  compatibility_flags = var.compatibility_flags

  bindings   = local.all_bindings
  migrations = local.migrations

  lifecycle {
    # wrangler deploy owns content, compat settings, AND bindings after bootstrap.
    # Bindings are included because wrangler commonly adds secrets (via
    # `wrangler secret put`) and plain_text env vars (via [vars] in
    # wrangler.toml) that TF shouldn't strip on next plan.
    # TF still creates the INITIAL bindings from module inputs — the lifecycle
    # only ignores drift after creation.
    ignore_changes = [
      content,
      compatibility_date,
      compatibility_flags,
      bindings,
    ]
  }
}

# Route: only created when route_pattern is non-empty.
resource "cloudflare_workers_route" "this" {
  count = var.route_pattern != "" ? 1 : 0

  zone_id = var.zone_id
  pattern = var.route_pattern
  script  = cloudflare_workers_script.this.script_name
}

# Cron triggers: CF provider v5 uses `schedules` (list of { cron = "..." } objects).
# Only created when at least one schedule is provided.
resource "cloudflare_workers_cron_trigger" "this" {
  count = length(var.cron_triggers) > 0 ? 1 : 0

  account_id  = var.account_id
  script_name = cloudflare_workers_script.this.script_name

  schedules = [
    for schedule in var.cron_triggers : {
      cron = schedule
    }
  ]
}
