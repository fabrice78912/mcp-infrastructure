resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name                    = "${var.environment}/${var.project_name}/${each.key}"
  description             = each.value.description
  recovery_window_in_days = var.recovery_window_days

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "secrets" {
  for_each = var.secrets

  secret_id     = aws_secretsmanager_secret.secrets[each.key].id
  secret_string = jsonencode(each.value.secret_data)
}