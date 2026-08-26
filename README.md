# terraform-cloudflare-modules

Reusable Terraform modules for Cloudflare infrastructure.

## Provider

All modules target the Cloudflare v5 provider:

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
```

## Modules

| Module | What it does | Primary inputs | Intended use |
|--------|--------------|----------------|--------------|
| [cf-worker-full](./modules/cf-worker-full) | Creates a Worker script, optional route, and Worker bindings. | `account_id`, `worker_name`, `zone_id`, `compatibility_date`; optional route and bindings | Manage Worker configuration while deploying application code separately. |
| [cf-pages-site](./modules/cf-pages-site) | Creates a Pages project, custom domain, and proxied DNS CNAME. | `account_id`, `project_name`, `zone_id`, `custom_domain`; optional service bindings | Publish a Pages site at a custom domain. |
| [cf-rate-limit](./modules/cf-rate-limit) | Creates a zone-level HTTP rate-limiting ruleset. | `zone_id`, `ruleset_name`, `rules` | Protect selected zone endpoints with rate limits. |
| [cf-zone-settings](./modules/cf-zone-settings) | Applies TLS, security, privacy, and performance settings to a zone. | `zone_id`; optional documented zone-setting values | Apply a consistent zone configuration. |
| [cf-access-app](./modules/cf-access-app) | Creates a Zero Trust Access application and optional email allowlist policy. | `account_id`, `app_name`, `domain`; optional IdP and session settings | Protect a self-hosted web application with Access. |
| [cf-scoped-token](./modules/cf-scoped-token) | Creates an API token with declared policies. | `name`, `policies` | Issue a narrowly scoped token for automation. |
| [cf-hyperdrive](./modules/cf-hyperdrive) | Creates a Hyperdrive configuration for PostgreSQL connection pooling. | `account_id`, `name`, `origin_database_url` | Connect Workers to a PostgreSQL origin through Hyperdrive. |
| [cf-d1](./modules/cf-d1) | Creates a D1 database. | `account_id`, `name`; optional `primary_location_hint` | Provision a D1 database for a Worker application. |
| [cf-kv](./modules/cf-kv) | Creates a Workers KV namespace. | `account_id`, `title` | Provision a KV namespace for Worker bindings. |
| [cf-dns-record](./modules/cf-dns-record) | Creates a DNS record with proxy, comment, and tag support. | `zone_id`, `name`, `type`, `content`; optional record settings | Manage a DNS record in an existing zone. |

## Usage

Reference modules via git source in your Terraform configuration:

```hcl
module "my_worker" {
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-worker-full?ref=v0.2.0"

  account_id    = var.cloudflare_account_id
  worker_name   = "example-worker"
  zone_id       = var.zone_id
  compatibility_date = var.worker_compatibility_date
  route_pattern = "api.example.invalid/*"

  kv_bindings = {
    CONFIG = cloudflare_workers_kv_namespace.config.id
  }
}
```

Pin to a specific version once tags are released:

```hcl
source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-worker-full?ref=v0.2.0"
```

## Conventions

- **Module structure** — each module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (some legacy modules still inline vars/outputs in main.tf — will be normalized)
- **Placeholder content** — Worker content is deployed via `wrangler`, not Terraform. Modules use a placeholder and ignore content drift via `lifecycle.ignore_changes`
- **Bindings** — passed as maps/lists of objects for flexibility (CF v5 unified bindings schema)
- **Route creation** — `route_pattern = ""` disables route creation in cf-worker-full

## Versioning

- `main` branch = latest development version
- Tags `v0.x.y` identify released versions
- Breaking changes bump major
- New modules or non-breaking additions bump minor

## License

Licensed under the [Apache License 2.0](./LICENSE).
