terraform {
  required_version = "~> 1.14.0"
}

variable "revision" {
  type    = string
  default = "v3"


  validation {
    condition     = can(regex("^v[0-9]+$", var.revision))
    error_message = "Use v seguido de numero, por exemplo v2."
  }
}

# Synthetic data only: local state is intentionally ephemeral in this demo.
resource "terraform_data" "release" {
  input = {
    service     = "portfolio-demo"
    environment = "prod-demo"
    revision    = var.revision
  }
}

output "release" {
  value = terraform_data.release.output
}
