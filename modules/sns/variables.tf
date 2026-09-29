variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "enable_encryption" {
  description = "Enable encryption for SNS topics"
  type        = bool
  default     = true
}

variable "topics" {
  description = "Map of SNS topics to create"
  type = map(object({
    display_name = string
  }))
  default = {}
}

variable "subscriptions" {
  description = "Map of SNS topic subscriptions"
  type = map(object({
    topic_key     = string
    protocol      = string
    endpoint      = string
    filter_policy = optional(string)
  }))
  default = {}
}