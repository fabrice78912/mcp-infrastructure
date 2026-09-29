output "topic_arns" {
  description = "Map of SNS topic ARNs"
  value       = { for k, v in aws_sns_topic.this : k => v.arn }
}

output "topic_ids" {
  description = "Map of SNS topic IDs"
  value       = { for k, v in aws_sns_topic.this : k => v.id }
}