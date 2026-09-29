output "api_gateway_url" {
  description = "API Gateway URL"
  value       = module.api_gateway.api_url
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.api_gateway.api_id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = module.dynamodb.table_arn
}

output "lambda_function_arns" {
  description = "Map of Lambda function ARNs"
  value       = module.lambda.function_arns
}

output "state_machine_arns" {
  description = "Map of Step Functions state machine ARNs"
  value       = module.step_functions.state_machine_arns
}

output "sqs_queue_urls" {
  description = "Map of SQS queue URLs"
  value       = module.sqs.queue_urls
}

output "msk_bootstrap_servers" {
  description = "MSK bootstrap servers"
  value       = module.msk.bootstrap_brokers
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard name"
  value       = module.cloudwatch.dashboard_name
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    environment    = var.environment
    region         = var.aws_region
    lambda_count   = length(module.lambda.function_arns)
    state_machines = length(module.step_functions.state_machine_arns)
    alarms_enabled = var.enable_cloudwatch_alarms
    backup_enabled = var.enable_dynamodb_backup
    deployed_at    = timestamp()
  }
}