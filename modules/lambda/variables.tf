variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "functions" {
  description = "Map of Lambda functions to create"
  type = map(object({
    handler       = string
    runtime       = string
    memory_size   = number
    timeout       = number
    environment_vars = map(string)
    vpc_config = optional(object({
      subnet_ids         = list(string)
      security_group_ids = list(string)
    }))
  }))
}

variable "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for Lambda functions"
  type        = number
  default     = -1 # No limit
}

# Phone Update Workflow variables
variable "lambda_code_bucket" {
  description = "S3 bucket containing Lambda deployment packages"
  type        = string
}

variable "code_version" {
  description = "Version of the Lambda code (e.g., 1.0.0)"
  type        = string
  default     = "1.0.0"
}

variable "dynamodb_client_table_name" {
  description = "Name of the DynamoDB client profile table"
  type        = string
}

variable "dynamodb_phone_history_table_name" {
  description = "Name of the DynamoDB phone history table"
  type        = string
}

variable "dynamodb_otp_table_name" {
  description = "Name of the DynamoDB OTP codes table"
  type        = string
}

variable "sqs_fraud_review_queue_url" {
  description = "URL of the SQS fraud review queue"
  type        = string
}

variable "mdmae_api_endpoint" {
  description = "MDMAE API endpoint"
  type        = string
}

variable "fcc_api_endpoint" {
  description = "FCC API endpoint"
  type        = string
}

variable "crm_api_endpoint" {
  description = "CRM API endpoint"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for SMS"
  type        = string
}

variable "log_level" {
  description = "Log level for Lambda functions"
  type        = string
  default     = "INFO"
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of API Gateway"
  type        = string
}

variable "step_functions_phone_update_arn" {
  description = "ARN of the phone update Step Functions state machine"
  type        = string
}