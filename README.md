# terraform-cloudflare-modules

Reusable Terraform modules for Cloudflare infrastructure.

## Provider

All modules are written for the Cloudflare v5 provider schema and pin `~> 5.0`:

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
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-worker-full?ref=v0.3.0"

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
source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-worker-full?ref=v0.3.0"
```

## Conventions

- **Module structure** — each module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
- **Placeholder content** — Worker content is deployed via `wrangler`, not Terraform. Modules use a placeholder and ignore content drift via `lifecycle.ignore_changes`
- **Bindings** — passed as maps/lists of objects for flexibility (CF v5 unified bindings schema)
- **Route creation** — `route_pattern = ""` disables route creation in cf-worker-full

## Checks

- What it reads: an export of the Git index (`git add` what you want checked); untracked and unstaged paths are not exported; Git configuration and `info/attributes` still apply.
- What it requires: the five files per module; every `variable` and `output` declared in `variables.tf`/`outputs.tf` as a column-zero canonical header with an ASCII name, a line beginning exactly `  description =`, and a column-zero `}`; no `.tofu` or JSON configuration in a module root.
- What it refuses before running tofu: a fixed lexical profile, not an HCL parser—`/*` and `<<` anywhere in `variables.tf`/`outputs.tf`, `/*` outside strings in any other module-root `.tf`, `/*` and `<<` outside strings in README examples and test files, a `}` followed by text, a `module`/`run` header that is not canonical or still open at end of file, a test file outside the module root and `tests/`, or a `?ref=` that is not a literal ref; the header of `scripts/check-modules.sh` is the complete list.
- What it runs: `tofu fmt -check`, then per module `init`, `validate`, `test`, then each README's single column-zero ```` ```hcl ```` example with its source pointed at the local copy, through `init` and `validate`; tofu receives only `PATH`, an empty `HOME`, a private `TMPDIR`, and the plugin cache; there is no provider lock file, so each `init` takes the newest provider matching `~> 5.0`; this is not a sandbox: run it only on a branch you would run a script from.
- What it needs and where it runs: Git 2.40 or later, OpenTofu, GNU awk, coreutils, findutils, grep and sed, and network access to the registry; locally before pushing, and in CI on every push to `main` and every pull request into `main` ([`.github/workflows/check-modules.yml`](.github/workflows/check-modules.yml); on a pull request the check judges the prospective merge).

## Versioning

- `main` branch = latest development version
- Tags `v0.x.y` identify released versions
- Breaking changes bump major
- New modules or non-breaking additions bump minor

## License

Licensed under the [Apache License 2.0](./LICENSE).
