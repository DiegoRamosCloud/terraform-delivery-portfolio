mock_provider "aws" {}

variables {
  aws_account_id            = "123456789012"
  bucket_name               = "portfolio-test-no-real-resources"
  github_subject_repository = "owner@123/repo@456"
}

run "least_privilege" {
  command = plan

  assert {
    condition = alltrue([
      for function in ["plan", "drift"] :
      !contains(flatten([for s in jsondecode(aws_iam_role_policy.delivery[function].policy).Statement : s.Action]), "ssm:PutParameter") &&
      !contains(flatten([for s in jsondecode(aws_iam_role_policy.delivery[function].policy).Statement : s.Action]), "ssm:DeleteParameter")
    ])
    error_message = "Plan e drift nao podem escrever/apagar SSM."
  }

  assert {
    condition = alltrue([
      for function in ["plan", "drift"] :
      one([for s in jsondecode(aws_iam_role_policy.delivery[function].policy).Statement : s.Action if s.Sid == "StateObject"]) == ["s3:GetObject"]
    ])
    error_message = "Plan e drift so podem ler o objeto de state."
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(aws_iam_role_policy.delivery["apply"].policy).Statement : s.Action]), "ssm:PutParameter")
    error_message = "Apply precisa gravar o parametro."
  }

  assert {
    condition = alltrue([
      for function in keys(local.roles) :
      one([for s in jsondecode(aws_iam_role_policy.delivery[function].policy).Statement : s.Resource if s.Sid == "DescribeParametersForProviderRead"]) == ["*"] &&
      one([for s in jsondecode(aws_iam_role_policy.delivery[function].policy).Statement : s.Action if s.Sid == "DescribeParametersForProviderRead"]) == ["ssm:DescribeParameters"]
    ])
    error_message = "O provider le metadados do SSM com DescribeParameters, que nao aceita ARN de parametro."
  }

  assert {
    condition = alltrue([
      for function, environment in local.roles :
      jsondecode(aws_iam_role.delivery[function].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:owner@123/repo@456:environment:${environment}"
    ])
    error_message = "Trust deve exigir repo e environment exatos, sem wildcard."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.delivery.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Este laboratorio usa SSE-S3, nao KMS."
  }
}
