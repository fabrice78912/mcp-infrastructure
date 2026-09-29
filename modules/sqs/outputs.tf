output "queue_urls" {
  description = "Map of SQS queue URLs"
  value       = { for k, v in aws_sqs_queue.queues : k => v.url }
}

output "queue_arns" {
  description = "Map of SQS queue ARNs"
  value       = { for k, v in aws_sqs_queue.queues : k => v.arn }
}

output "dlq_urls" {
  description = "Map of DLQ URLs"
  value       = { for k, v in aws_sqs_queue.dlq : k => v.url }
}

output "dlq_arns" {
  description = "Map of DLQ ARNs"
  value       = { for k, v in aws_sqs_queue.dlq : k => v.arn }
}

# Fraud Review Queue outputs
output "fraud_review_queue_url" {
  description = "URL of the Fraud Review Queue"
  value       = aws_sqs_queue.fraud_review_queue.url
}

output "fraud_review_queue_arn" {
  description = "ARN of the Fraud Review Queue"
  value       = aws_sqs_queue.fraud_review_queue.arn
}

output "fraud_review_dlq_url" {
  description = "URL of the Fraud Review DLQ"
  value       = aws_sqs_queue.fraud_review_dlq.url
}

output "fraud_review_dlq_arn" {
  description = "ARN of the Fraud Review DLQ"
  value       = aws_sqs_queue.fraud_review_dlq.arn
}