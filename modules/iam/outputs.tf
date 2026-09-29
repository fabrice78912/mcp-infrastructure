output "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "stepfunctions_execution_role_arn" {
  description = "ARN of Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution.arn
}

output "stepfunctions_execution_role_name" {
  description = "Name of Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution.name
}

output "api_gateway_cloudwatch_role_arn" {
  description = "ARN of API Gateway CloudWatch role"
  value       = aws_iam_role.api_gateway_cloudwatch.arn
}

output "eventbridge_invoke_lambda_role_arn" {
  description = "ARN of EventBridge role to invoke Lambda"
  value       = aws_iam_role.eventbridge_invoke_lambda.arn
}