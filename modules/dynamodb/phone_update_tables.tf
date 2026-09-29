# Table pour l'historique des changements de numéro de téléphone
resource "aws_dynamodb_table" "phone_number_history" {
  name           = "${var.environment}-PhoneNumberHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "clientId"
  range_key      = "timestamp"

  attribute {
    name = "clientId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # TTL pour auto-suppression après 180 jours (15552000 secondes)
  ttl {
    enabled        = true
    attribute_name = "expiresAt"
  }

  # Point-in-Time Recovery pour backup
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-PhoneNumberHistory"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "Phone update history tracking"
  }
}

# Table pour les codes OTP
resource "aws_dynamodb_table" "otp_codes" {
  name           = "${var.environment}-OTPCodes"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "clientId"
  range_key      = "otpId"

  attribute {
    name = "clientId"
    type = "S"
  }

  attribute {
    name = "otpId"
    type = "S"
  }

  # Index secondaire pour rechercher par OTP ID uniquement
  global_secondary_index {
    name            = "OTPIdIndex"
    hash_key        = "otpId"
    projection_type = "ALL"
  }

  # TTL pour auto-suppression des codes expirés (5 minutes)
  ttl {
    enabled        = true
    attribute_name = "expiresAt"
  }

  # Point-in-Time Recovery
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-OTPCodes"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "OTP code storage and validation"
  }
}