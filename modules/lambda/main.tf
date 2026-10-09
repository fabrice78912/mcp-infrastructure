resource "aws_lambda_function" "functions" {
  for_each = var.functions

  function_name = "${var.environment}-${var.project_name}-${each.key}"
  role          = var.lambda_execution_role_arn

  # Deployment package from S3
  # Java21 functions (Spring Boot) share the same JAR, Java17 functions have their own JARs
  s3_bucket        = var.lambda_code_bucket
  s3_key           = each.value.runtime == "java21" ? "orchestration/mcp-orchestration-${var.code_version}-aws.jar" : "${each.key}.jar"
  source_code_hash = each.value.runtime == "java21" ? base64sha256("orchestration-${var.code_version}") : base64sha256("${each.key}-${var.code_version}")

  # Runtime configuration
  handler     = each.value.handler
  runtime     = each.value.runtime
  memory_size = each.value.memory_size
  timeout     = each.value.timeout
  architectures = ["arm64"]

  # Environment variables
  dynamic "environment" {
    for_each = length(each.value.environment_vars) > 0 ? [1] : []
    content {
      variables = each.value.environment_vars
    }
  }

  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = each.value.vpc_config != null ? [each.value.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Function    = each.key
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = var.functions

  name              = "/aws/lambda/${var.environment}-${var.project_name}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Lambda permissions for various triggers
resource "aws_lambda_permission" "api_gateway" {
  for_each = { for k, v in var.functions : k => v if can(regex("client-profile-reader", k)) }

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = { for k, v in var.functions : k => v if can(regex("mq-poller", k)) }

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.key].function_name
  principal     = "events.amazonaws.com"
}

resource "aws_lambda_permission" "step_functions" {
  for_each = {
    for k, v in var.functions : k => v
    if can(regex("name-validator|mdmae-client|fcc-sender|human-review-handler", k))
  }

  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.key].function_name
  principal     = "states.amazonaws.com"
}