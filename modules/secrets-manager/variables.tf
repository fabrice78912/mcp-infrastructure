variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "secrets" {
  description = "Map of secrets to create"
  type = map(object({
    description = string
    secret_data = map(string)
  }))
}

variable "recovery_window_days" {
  description = "Number of days to retain deleted secrets"
  type        = number
  default     = 7
}