locals {
  state_key     = "portfolio/hml/ssm/terraform.tfstate"
  parameter_arn = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/portfolio/hml/release/revision"
  bucket_arn    = "arn:aws:s3:::${var.bucket_name}"
  roles = {
    plan  = "hml-plan"
    apply = "hml"
    drift = "hml-drift"
  }
}

# The account already has this provider. Do not take ownership of other labs' identity.
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_s3_bucket" "delivery" {
  bucket        = var.bucket_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "delivery" {
  bucket                  = aws_s3_bucket.delivery.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "delivery" {
  bucket = aws_s3_bucket.delivery.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "delivery" {
  bucket = aws_s3_bucket.delivery.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "delivery" {
  bucket = aws_s3_bucket.delivery.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "tls" {
  bucket = aws_s3_bucket.delivery.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# Expire plans, never state/history. Lifecycle expiration is asynchronous.
resource "aws_s3_bucket_lifecycle_configuration" "plans" {
  bucket = aws_s3_bucket.delivery.id
  rule {
    id     = "expire-private-plans"
    status = "Enabled"
    filter {
      prefix = "plans/"
    }
    expiration {
      days = 1
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
  depends_on = [aws_s3_bucket_versioning.delivery]
}

resource "aws_iam_role" "delivery" {
  for_each             = local.roles
  name                 = "portfolio-hml-${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_subject_repository}:environment:${each.value}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "delivery" {
  for_each = local.roles
  name     = "portfolio-hml-${each.key}"
  role     = aws_iam_role.delivery[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "ListDedicatedBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.bucket_arn]
      },
      {
        Sid      = "StateObject"
        Effect   = "Allow"
        Action   = each.key == "apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
        Resource = ["${local.bucket_arn}/${local.state_key}"]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.bucket_arn}/${local.state_key}.tflock"]
      },
      {
        Sid      = "ReadReleaseParameter"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"]
        Resource = [local.parameter_arn]
      },
      {
        Sid      = "DescribeParametersForProviderRead"
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = ["*"]
      }
      ], each.key == "apply" ? [{
        Sid      = "WriteReleaseParameter"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource"]
        Resource = [local.parameter_arn]
        }] : [], each.key != "drift" ? [{
        Sid      = "PrivatePlanExchange"
        Effect   = "Allow"
        Action   = each.key == "plan" ? ["s3:PutObject"] : ["s3:GetObject"]
        Resource = ["${local.bucket_arn}/plans/hml/*"]
    }] : [])
  })
}
