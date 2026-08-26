resource "cloudflare_d1_database" "this" {
  account_id            = var.account_id
  name                  = var.name
  primary_location_hint = var.primary_location_hint

  lifecycle {
    # read_replication is auto-managed by CF after initial create and drifts
    # on every plan if not ignored (new replicas added by CF, etc.)
    ignore_changes = [read_replication]
  }
}
