resource "aws_sqs_queue" "queues" {
  for_each = var.queues

  name                       = "${var.environment}-${var.project_name}-${each.key}"
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  message_retention_seconds  = each.value.message_retention_seconds

  # Dead Letter Queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Queue       = each.key
  }
}

resource "aws_sqs_queue" "dlq" {
  for_each = var.queues

  name                      = "${var.environment}-${var.project_name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Queue       = "${each.key}-dlq"
  }
}