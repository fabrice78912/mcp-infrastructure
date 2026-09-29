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

# Phone Update Workflow outputs
output "phone_update_function_arns" {
  description = "Map of phone update Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.phone_update_functions : k => v.arn }
}

output "phone_update_function_names" {
  description = "Map of phone update Lambda function names"
  value       = { for k, v in aws_lambda_function.phone_update_functions : k => v.function_name }
}

output "phone_update_controller_arn" {
  description = "ARN of the phone update controller Lambda"
  value       = aws_lambda_function.phone_update_functions["phone-update-controller"].arn
}

output "phone_update_controller_invoke_arn" {
  description = "Invoke ARN of the phone update controller Lambda (for API Gateway)"
  value       = aws_lambda_function.phone_update_functions["phone-update-controller"].invoke_arn
}