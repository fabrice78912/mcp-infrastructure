variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to invoke"
  type        = string
}

variable "cloudwatch_role_arn" {
  description = "ARN of IAM role for API Gateway CloudWatch logging"
  type        = string
  default     = ""
}

variable "throttle_burst_limit" {
  description = "Throttle burst limit for API Gateway"
  type        = number
  default     = 100
}

variable "throttle_rate_limit" {
  description = "Throttle rate limit for API Gateway (requests per second)"
  type        = number
  default     = 50
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# Phone Update Workflow variables (optional)
variable "phone_update_controller_invoke_arn" {
  description = "Invoke ARN of the phone update controller Lambda function"
  type        = string
  default     = ""
}

variable "phone_update_controller_arn" {
  description = "ARN of the phone update controller Lambda function (for OpenAPI spec)"
  type        = string
  default     = ""
}

variable "phone_update_status_checker_arn" {
  description = "ARN of the phone update status checker Lambda function (for OpenAPI spec)"
  type        = string
  default     = ""
}

# Swagger/OpenAPI Documentation variables
variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for Swagger documentation"
  type        = bool
  default     = false
}

variable "api_version" {
  description = "API version for documentation"
  type        = string
  default     = "1.0.0"
}