variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mcp"
}

variable "vpc_id" {
  description = "VPC ID for MSK cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for MSK cluster"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for MSK cluster"
  type        = list(string)
}

variable "kafka_topics" {
  description = "Map of Kafka topics to create"
  type = map(object({
    partitions         = number
    replication_factor = number
  }))
  default = {}
}