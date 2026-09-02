mock_provider "cloudflare" {}

variables {
  account_id    = "0123456789abcdef0123456789abcdef"
  project_name  = "example-pages-site"
  zone_id       = "fedcba9876543210fedcba9876543210"
  custom_domain = "app.example.invalid"
}

run "rejects_duplicate_service_binding" {
  command = plan

  variables {
    service_bindings = [
      { name = "EXAMPLE_SERVICE", service = "example-worker-one" },
      { name = "EXAMPLE_SERVICE", service = "example-worker-two" },
    ]
  }

  expect_failures = [var.service_bindings]
}

run "rejects_duplicate_empty_service_binding_name" {
  command = plan

  variables {
    service_bindings = [
      { name = "", service = "example-worker-one" },
      { name = "", service = "example-worker-two" },
    ]
  }

  expect_failures = [var.service_bindings]
}

run "accepts_distinct_service_bindings" {
  command = plan

  variables {
    service_bindings = [
      { name = "EXAMPLE_SERVICE_ONE", service = "example-worker-one" },
      { name = "EXAMPLE_SERVICE_TWO", service = "example-worker-two" },
    ]
  }
}
