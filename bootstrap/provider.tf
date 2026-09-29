terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend LOCAL pour bootstrap (pas de S3 encore!)
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "bootstrap"
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Purpose     = "Infrastructure Bootstrap"
    }
  }
}