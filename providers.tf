provider "aws" {
  region = var.aws_region

  # Tags applied to every resource Terraform creates -> easy cost tracking
  # and easy identification in the AWS console.
  default_tags {
    tags = {
      Project   = var.project_name
      Course    = "CSEBSEPCP01_E"
      ManagedBy = "Terraform"
    }
  }
}
