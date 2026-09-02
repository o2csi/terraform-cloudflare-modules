mock_provider "cloudflare" {}

variables {
  account_id = "0123456789abcdef0123456789abcdef"
  name       = "example-hyperdrive"
}

run "rejects_second_at" {
  command = plan

  variables {
    origin_database_url = "postgres://u:p@ss@h:5432/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_percent" {
  command = plan

  variables {
    origin_database_url = "postgres://u:p%40ss@h:5432/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_query_string" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:5432/db?sslmode=require"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_fragment" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:5432/db#frag"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_ipv6_literal" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@[::1]:5432/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_missing_port" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_empty_database" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:5432/"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_empty_user" {
  command = plan

  variables {
    origin_database_url = "postgres://:pass@h:5432/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_database_slash" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:5432/db/x"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_mysql_scheme" {
  command = plan

  variables {
    origin_database_url = "mysql://u:pass@h:3306/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_port_zero" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:0/db"
  }

  expect_failures = [var.origin_database_url]
}

run "rejects_port_above_65535" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:65536/db"
  }

  expect_failures = [var.origin_database_url]
}

run "accepts_canonical_url" {
  command = plan

  variables {
    origin_database_url = "postgresql://example_user:example_password@db.example.invalid:5432/example_database"
  }
}

run "accepts_port_65535" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pass@h:65535/db"
  }
}

run "accepts_password_colon_and_slash" {
  command = plan

  variables {
    origin_database_url = "postgres://u:pa:ss/w0rd@h:5432/db"
  }
}
