output "function_arns" {
  description = "Map of Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.functions : k => v.arn }
}

output "function_names" {
  description = "Map of Lambda function names"
  value       = { for k, v in aws_lambda_function.functions : k => v.function_name }
}

output "function_invoke_arns" {
  description = "Map of Lambda function invoke ARNs (for API Gateway)"
  value       = { for k, v in aws_lambda_function.functions : k => v.invoke_arn }
}

output "log_group_names" {
  description = "Map of CloudWatch log group names"
  value       = { for k, v in aws_cloudwatch_log_group.lambda_logs : k => v.name }
}