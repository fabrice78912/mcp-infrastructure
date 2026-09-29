resource "aws_sfn_state_machine" "state_machines" {
  for_each = var.state_machines

  name     = "${var.environment}-${var.project_name}-${each.key}"
  role_arn = each.value.role_arn

  definition = templatefile(
    "${path.module}/${each.value.definition_template}",
    each.value.template_vars
  )

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs[each.key].arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  for_each = var.state_machines

  name              = "/aws/states/${var.environment}-${var.project_name}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}