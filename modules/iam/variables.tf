variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "dynamodb_table_arn" {
  description = "ARN of DynamoDB table"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of SQS queue"
  type        = string
}

variable "msk_cluster_arn" {
  description = "ARN of MSK cluster"
  type        = string
  default     = "*"
}

variable "secrets_arns" {
  description = "List of Secrets Manager ARNs"
  type        = list(string)
  default     = []
}

# Phone Update Workflow variables (optional)
variable "phone_history_table_arn" {
  description = "ARN of Phone Number History table"
  type        = string
  default     = ""
}

variable "otp_codes_table_arn" {
  description = "ARN of OTP Codes table"
  type        = string
  default     = ""
}

variable "fraud_review_queue_arn" {
  description = "ARN of Fraud Review SQS queue"
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for OTP SMS"
  type        = string
  default     = ""
}

variable "phone_update_state_machine_arn" {
  description = "ARN of Phone Update Step Functions state machine"
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = ""
}