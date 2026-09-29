variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "queues" {
  description = "Map of SQS queues to create"
  type = map(object({
    visibility_timeout_seconds = number
    message_retention_seconds  = number
    max_receive_count         = number
  }))
}

variable "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine (for SQS queue policy)"
  type        = string
  default     = "*"
}