variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "state_machines" {
  description = "Map of Step Functions state machines to create"
  type = map(object({
    definition_template = string
    role_arn           = string
    template_vars      = map(string)
  }))
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}