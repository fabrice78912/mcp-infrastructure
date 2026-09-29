variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "rules" {
  description = "Map of EventBridge rules to create"
  type = map(object({
    description         = string
    schedule_expression = string
    target_lambda_arn   = string
  }))
}

variable "eventbridge_role_arn" {
  description = "ARN of IAM role for EventBridge to invoke Lambda"
  type        = string
}