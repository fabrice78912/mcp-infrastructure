# ========================================
# S3 Bucket for Terraform State - DEV
# ========================================

resource "aws_s3_bucket" "terraform_state_dev" {
  bucket = var.terraform_state_bucket_name_dev

  tags = {
    Name        = var.terraform_state_bucket_name_dev
    Description = "Terraform state storage for dev environment"
    Environment = "dev"
  }
}

# Versioning pour le bucket state dev
resource "aws_s3_bucket_versioning" "terraform_state_dev" {
  bucket = aws_s3_bucket.terraform_state_dev.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement pour le bucket state dev
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_dev" {
  bucket = aws_s3_bucket.terraform_state_dev.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquer l'accès public au bucket state dev
resource "aws_s3_bucket_public_access_block" "terraform_state_dev" {
  bucket = aws_s3_bucket.terraform_state_dev.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle pour archiver les anciennes versions
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_dev" {
  bucket = aws_s3_bucket.terraform_state_dev.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# ========================================
# S3 Bucket for Terraform State - PROD
# ========================================

resource "aws_s3_bucket" "terraform_state_prod" {
  bucket = var.terraform_state_bucket_name_prod

  tags = {
    Name        = var.terraform_state_bucket_name_prod
    Description = "Terraform state storage for prod environment"
    Environment = "prod"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_prod" {
  bucket = aws_s3_bucket.terraform_state_prod.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_prod" {
  bucket = aws_s3_bucket.terraform_state_prod.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_prod" {
  bucket = aws_s3_bucket.terraform_state_prod.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_prod" {
  bucket = aws_s3_bucket.terraform_state_prod.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# ========================================
# S3 Bucket for Lambda Artifacts
# ========================================

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = var.lambda_artifacts_bucket_name

  tags = {
    Name        = var.lambda_artifacts_bucket_name
    Description = "Lambda deployment artifacts"
  }
}

# Versioning pour les artifacts
resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement pour les artifacts
resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquer l'accès public aux artifacts
resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle pour nettoyer les anciens JARs
resource "aws_s3_bucket_lifecycle_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    id     = "cleanup-old-artifacts"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ========================================
# DynamoDB Table for State Locking - DEV
# ========================================

resource "aws_dynamodb_table" "terraform_lock_dev" {
  name         = var.dynamodb_lock_table_name_dev
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = var.dynamodb_lock_table_name_dev
    Description = "Terraform state locking for dev"
    Environment = "dev"
  }
}

# ========================================
# DynamoDB Table for State Locking - PROD
# ========================================

resource "aws_dynamodb_table" "terraform_lock_prod" {
  name         = var.dynamodb_lock_table_name_prod
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = var.dynamodb_lock_table_name_prod
    Description = "Terraform state locking for prod"
    Environment = "prod"
  }
}

# ========================================
# IAM User for Terraform (Optionnel)
# ========================================

resource "aws_iam_user" "terraform_deployer" {
  count = var.create_iam_user ? 1 : 0

  name = var.iam_user_name
  path = "/terraform/"

  tags = {
    Name        = var.iam_user_name
    Description = "Terraform deployment user"
  }
}

# Policy pour accès complet (AdministratorAccess)
resource "aws_iam_user_policy_attachment" "terraform_deployer_admin" {
  count = var.create_iam_user ? 1 : 0

  user       = aws_iam_user.terraform_deployer[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ========================================
# IAM Role pour GitHub Actions (OIDC - Recommandé)
# ========================================

# Créer un OIDC provider pour GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1b511abead59c6ce207077c0bf0e0043b1382612", "6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# Rôle IAM pour GitHub Actions (sans credentials à stocker!)
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Remplacer par votre organisation/repo GitHub
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# Attacher AdministratorAccess au rôle
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}