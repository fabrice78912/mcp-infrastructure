output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.client_profile.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.client_profile.arn
}

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.client_profile.id
}