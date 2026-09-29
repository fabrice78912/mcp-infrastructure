variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ca-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "code_version" {
  description = "Version of Lambda deployment packages"
  type        = string
  default     = "1.0.0"
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
  default     = "DEV.APP.SVRCONN"
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

# Configuration dev-specific
variable "lambda_memory_size" {
  description = "Lambda memory size (MB)"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout (seconds)"
  type        = number
  default     = 60
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch logs retention (days)"
  type        = number
  default     = 3
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = false
}

variable "enable_dynamodb_backup" {
  description = "Enable DynamoDB Point-in-Time Recovery"
  type        = bool
  default     = false
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests/second)"
  type        = number
  default     = 100
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 200
}

variable "msk_partitions" {
  description = "Number of partitions for MSK topics"
  type        = number
  default     = 1
}