variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "table_name" {
  description = "Name of DynamoDB table"
  type        = string
  default     = "ClientProfile"
}

variable "enable_point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery for backups"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable server-side encryption"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}