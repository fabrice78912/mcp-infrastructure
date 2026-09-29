variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "enable_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = false
}

variable "lambda_function_names" {
  description = "Map of Lambda function names for monitoring"
  type        = map(string)
  default     = {}
}

variable "state_machine_arns" {
  description = "Map of Step Functions state machine ARNs for monitoring"
  type        = map(string)
  default     = {}
}

variable "api_gateway_name" {
  description = "Name of the API Gateway for monitoring"
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}

variable "error_threshold" {
  description = "Error count threshold for alarms"
  type        = number
  default     = 10
}

variable "duration_threshold_ms" {
  description = "Lambda duration threshold in milliseconds"
  type        = number
  default     = 5000
}