terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state (optional, recommended). Create the bucket once, then
  # uncomment this block and run `terraform init -migrate-state`.
  # `use_lockfile` uses native S3 state locking (Terraform >= 1.10),
  # which replaces the older DynamoDB lock table.
  #
  # backend "s3" {
  #   bucket       = "REPLACE-ME-tfstate-bucket"
  #   key          = "cloud-programming/task1/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
