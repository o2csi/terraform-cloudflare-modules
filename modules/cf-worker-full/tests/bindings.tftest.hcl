mock_provider "cloudflare" {}

variables {
  account_id         = "0123456789abcdef0123456789abcdef"
  worker_name        = "example-worker"
  zone_id            = "fedcba9876543210fedcba9876543210"
  compatibility_date = "2026-01-01"
}

run "rejects_kv_and_plain_vars" {
  command = plan

  variables {
    kv_bindings = {
      DUPLICATE = "0123456789abcdef0123456789abcdef"
    }
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_durable_objects_and_plain_vars" {
  command = plan

  variables {
    durable_object_bindings = [
      { name = "DUPLICATE", class_name = "ExampleDurableObject" },
    ]
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_d1_and_plain_vars" {
  command = plan

  variables {
    d1_bindings = {
      DUPLICATE = "0123456789abcdef0123456789abcdef"
    }
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_hyperdrive_and_plain_vars" {
  command = plan

  variables {
    hyperdrive_bindings = {
      DUPLICATE = "0123456789abcdef0123456789abcdef"
    }
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_service_and_plain_vars" {
  command = plan

  variables {
    service_bindings = [
      { name = "DUPLICATE", service = "example-service" },
    ]
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_secrets_and_plain_vars" {
  command = plan

  variables {
    secret_names = ["DUPLICATE"]
    plain_vars = {
      DUPLICATE = "value"
    }
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_duplicate_secret_names" {
  command = plan

  variables {
    secret_names = ["DUPLICATE", "DUPLICATE"]
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "rejects_duplicate_empty_secret_names" {
  command = plan

  variables {
    secret_names = ["", ""]
  }

  expect_failures = [cloudflare_workers_script.this]
}

run "accepts_distinct_binding_names" {
  command = plan

  variables {
    kv_bindings = {
      KV_BINDING = "0123456789abcdef0123456789abcdef"
    }
    durable_object_bindings = [
      { name = "DO_BINDING", class_name = "ExampleDurableObject" },
    ]
    d1_bindings = {
      D1_BINDING = "0123456789abcdef0123456789abcdef"
    }
    hyperdrive_bindings = {
      HYPERDRIVE_BINDING = "0123456789abcdef0123456789abcdef"
    }
    service_bindings = [
      { name = "SERVICE_BINDING", service = "example-service" },
    ]
    secret_names = ["SECRET_BINDING"]
    plain_vars = {
      PLAIN_BINDING = "value"
    }
  }
}
