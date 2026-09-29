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

# Phone Number History Table outputs
output "phone_history_table_name" {
  description = "Name of the Phone Number History table"
  value       = aws_dynamodb_table.phone_number_history.name
}

output "phone_history_table_arn" {
  description = "ARN of the Phone Number History table"
  value       = aws_dynamodb_table.phone_number_history.arn
}

# OTP Codes Table outputs
output "otp_codes_table_name" {
  description = "Name of the OTP Codes table"
  value       = aws_dynamodb_table.otp_codes.name
}

output "otp_codes_table_arn" {
  description = "ARN of the OTP Codes table"
  value       = aws_dynamodb_table.otp_codes.arn
}