resource "aws_dynamodb_table" "client_profile" {
  name           = "${var.environment}-${var.table_name}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "clientId"

  attribute {
    name = "clientId"
    type = "S"
  }

  # Point-in-Time Recovery (backup continu)
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Encryption
  server_side_encryption {
    enabled = var.enable_encryption
  }

  # TTL (optionnel, désactivé par défaut)
  ttl {
    enabled        = false
    attribute_name = ""
  }

  tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}