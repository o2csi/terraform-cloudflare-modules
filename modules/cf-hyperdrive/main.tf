locals {
  # Parse the postgres URL into components using named capture groups.
  # Expected format: postgresql://<user>:<password>@<host>:<port>/<database>
  # Also handles the "postgres://" scheme variant used by some Supabase session pooler URLs.
  #
  # Named capture groups: user, password, host, port, database
  url_parts = regex(
    "^(?:postgresql|postgres)://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)$",
    var.origin_database_url
  )
}

resource "cloudflare_hyperdrive_config" "this" {
  account_id = var.account_id
  name       = var.name

  origin = {
    scheme   = "postgres"
    host     = local.url_parts["host"]
    port     = tonumber(local.url_parts["port"])
    database = local.url_parts["database"]
    user     = local.url_parts["user"]
    password = local.url_parts["password"]
  }

  caching = {
    # CF provider v5: `disabled = true` turns caching off; `disabled = false` enables it.
    disabled               = !var.caching_enabled
    max_age                = var.caching_max_age
    stale_while_revalidate = var.caching_stale_while_revalidate
  }
}
