mock_provider "aws" {}

variables {
  aws_account_id = "123456789012"
}

run "release_contract" {
  command = plan
  assert {
    condition     = aws_ssm_parameter.release.name == "/portfolio/hml/release/revision" && aws_ssm_parameter.release.type == "String" && aws_ssm_parameter.release.tier == "Standard"
    error_message = "O lab deve manter o parametro ficticio no escopo IAM de hml."
  }

  assert {
    condition     = aws_sqs_queue.release_events.name == "portfolio-hml-release-events" && aws_sqs_queue.release_events.sqs_managed_sse_enabled == true
    error_message = "A fila de eventos deve manter nome previsivel e criptografia SSE-SQS."
  }
}

run "invalid_revision" {
  command = plan
  variables {
    revision = "invalid"
  }
  expect_failures = [var.revision]
}

run "invalid_release_events_retention" {
  command = plan
  variables {
    release_events_retention_seconds = 30
  }
  expect_failures = [var.release_events_retention_seconds]
}
