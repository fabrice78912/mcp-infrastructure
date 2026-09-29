resource "aws_cloudwatch_event_rule" "rules" {
  for_each = var.rules

  name                = "${var.environment}-${var.project_name}-${each.key}"
  description         = each.value.description
  schedule_expression = each.value.schedule_expression

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_event_target" "lambda_targets" {
  for_each = var.rules

  rule      = aws_cloudwatch_event_rule.rules[each.key].name
  target_id = "lambda"
  arn       = each.value.target_lambda_arn
  role_arn  = var.eventbridge_role_arn
}