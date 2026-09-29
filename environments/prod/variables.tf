variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ca-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

# Secrets (passed from GitHub Actions)
variable "ibm_mq_host" {
  description = "IBM MQ host"
  type        = string
  sensitive   = true
}

variable "ibm_mq_port" {
  description = "IBM MQ port"
  type        = string
  sensitive   = true
  default     = "1414"
}

variable "ibm_mq_channel" {
  description = "IBM MQ channel"
  type        = string
  sensitive   = true
  default     = "PROD.APP.SVRCONN"
}

variable "ibm_mq_password" {
  description = "IBM MQ password"
  type        = string
  sensitive   = true
}

variable "mdmae_url" {
  description = "MDMAE service URL"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "Email for CloudWatch alarms"
  type        = string
  default     = ""
}

# Configuration prod-specific
variable "lambda_memory_size" {
  description = "Lambda memory size (MB)"
  type        = number
  default     = 1024
}

variable "lambda_timeout" {
  description = "Lambda timeout (seconds)"
  type        = number
  default     = 300
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch logs retention (days)"
  type        = number
  default     = 30
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "enable_dynamodb_backup" {
  description = "Enable DynamoDB Point-in-Time Recovery"
  type        = bool
  default     = true
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests/second)"
  type        = number
  default     = 200
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 400
}

variable "msk_partitions" {
  description = "Number of partitions for MSK topics"
  type        = number
  default     = 3
}