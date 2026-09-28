output "github_repository_variables" {
  value = {
    AWS_ACCOUNT_ID = var.aws_account_id
    AWS_REGION     = var.aws_region
    TFSTATE_BUCKET = aws_s3_bucket.delivery.id
  }
}

output "github_environment_roles" {
  value = { for function, environment in local.roles : environment => aws_iam_role.delivery[function].arn }
}

output "trusted_subjects" {
  value = { for function, environment in local.roles : function => "repo:${var.github_subject_repository}:environment:${environment}" }
}
