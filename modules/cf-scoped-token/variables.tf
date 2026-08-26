variable "name" {
  type        = string
  description = "Display name of the API token."
}

variable "policies" {
  type = list(object({
    effect = string
    # List of CF permission group IDs. The caller resolves these via
    # data "cloudflare_api_token_permission_groups" and passes the IDs here.
    permission_groups = list(string)
    # Resource selector map, e.g.:
    #   { "com.cloudflare.api.account.<id>" = "*" }
    # The value is passed to jsonencode() inside the resource, so the caller
    # provides a plain map(string) — no pre-encoding required.
    resources = map(string)
  }))
  description = "Access policies for the token. Each policy maps permission group IDs to resource selectors."
}
