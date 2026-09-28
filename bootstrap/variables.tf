variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe o ID da conta AWS do laboratorio com 12 digitos."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Use um nome S3 exclusivo, com 3 a 63 caracteres, letras minusculas, numeros e hifens."
  }
}

variable "github_subject_repository" {
  description = "Trecho entre repo: e :environment: do sub realmente emitido pelo GitHub."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.github_subject_repository))
    error_message = "Use OWNER@OWNER_ID/REPO@REPO_ID, sem wildcard; confirme no workflow de claims."
  }
}
