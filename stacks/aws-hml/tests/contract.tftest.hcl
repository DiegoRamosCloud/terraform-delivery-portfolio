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
}

run "invalid_revision" {
  command = plan
  variables {
    revision = "invalid"
  }
  expect_failures = [var.revision]
}
