variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ca-central-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "terraform_state_bucket_name_dev" {
  description = "S3 bucket name for Terraform state (dev)"
  type        = string
  default     = "mcp-terraform-state-dev"
}

variable "terraform_state_bucket_name_prod" {
  description = "S3 bucket name for Terraform state (prod)"
  type        = string
  default     = "mcp-terraform-state-prod"
}

variable "lambda_artifacts_bucket_name" {
  description = "S3 bucket name for Lambda artifacts"
  type        = string
  default     = "bnc-mcp-lambda-artifacts"
}

variable "dynamodb_lock_table_name_dev" {
  description = "DynamoDB table name for state locking (dev)"
  type        = string
  default     = "mcp-terraform-lock-dev"
}

variable "dynamodb_lock_table_name_prod" {
  description = "DynamoDB table name for state locking (prod)"
  type        = string
  default     = "mcp-terraform-lock-prod"
}

variable "create_iam_user" {
  description = "Create IAM user for Terraform deployment"
  type        = bool
  default     = false  # Mettre true si vous voulez créer l'utilisateur
}

variable "iam_user_name" {
  description = "IAM user name for Terraform"
  type        = string
  default     = "terraform-deployer"
}

variable "github_repo" {
  description = "GitHub repository for OIDC (format: org/repo)"
  type        = string
  default     = "your-org/mcp-infrastructure"  # À MODIFIER
}