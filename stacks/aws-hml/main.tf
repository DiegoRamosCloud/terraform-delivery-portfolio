terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
  backend "s3" {
    key                  = "portfolio/hml/ssm/terraform.tfstate"
    encrypt              = true
    use_lockfile         = true
    workspace_key_prefix = "workspaces"
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe uma conta AWS de 12 digitos."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "revision" {
  type    = string
  default = "v3"
  validation {
    condition     = can(regex("^v[0-9]+$", var.revision))
    error_message = "Use v seguido de numero, por exemplo v2."
  }
}

variable "release_events_retention_seconds" {
  type    = number
  default = 172800
  validation {
    condition     = var.release_events_retention_seconds >= 60 && var.release_events_retention_seconds <= 1209600
    error_message = "A retencao da fila deve ficar entre 60 segundos e 14 dias."
  }
}

resource "aws_ssm_parameter" "release" {
  name  = "/portfolio/hml/release/revision"
  type  = "String"
  tier  = "Standard"
  value = var.revision
  tags = {
    project     = "terraform-delivery-portfolio"
    environment = "hml"
    managed_by  = "terraform"
  }
}

resource "aws_sqs_queue" "release_events" {
  name                       = "portfolio-hml-release-events"
  message_retention_seconds  = var.release_events_retention_seconds
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true

  tags = {
    project     = "terraform-delivery-portfolio"
    environment = "hml"
    managed_by  = "terraform"
  }
}
