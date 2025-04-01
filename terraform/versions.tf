provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ai_ml_competition_2025_0"
      Owners      = "Noor"
      Provisioner = "Terraform"
    }
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.89.0"
    }
  }
  required_version = "=1.11.0"
}