terraform {
  backend "s3" {
    bucket         = "mcp-terraform-state-prod"
    key            = "infrastructure/terraform.tfstate"
    region         = "ca-central-1"
    encrypt        = true
    dynamodb_table = "mcp-terraform-lock-prod"
  }

  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "mcp"
      ManagedBy   = "Terraform"
    }
  }
}