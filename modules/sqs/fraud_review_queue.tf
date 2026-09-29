# SQS Queue for Fraud Review (Human Approval)
resource "aws_sqs_queue" "fraud_review_queue" {
  name                       = "${var.environment}-fraud-review-queue"
  visibility_timeout_seconds = 86400  # 24 hours (Step Functions timeout)
  message_retention_seconds  = 1209600  # 14 days
  delay_seconds              = 0
  max_message_size           = 262144  # 256 KB
  receive_wait_time_seconds  = 0

  # Dead Letter Queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_review_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.environment}-fraud-review-queue"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "Phone update fraud review queue"
  }
}

# Dead Letter Queue for failed fraud review messages
resource "aws_sqs_queue" "fraud_review_dlq" {
  name                      = "${var.environment}-fraud-review-queue-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "${var.environment}-fraud-review-queue-dlq"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "Dead letter queue for fraud review"
  }
}

# SQS Queue Policy to allow Step Functions to send messages
resource "aws_sqs_queue_policy" "fraud_review_policy" {
  queue_url = aws_sqs_queue.fraud_review_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.fraud_review_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = var.step_functions_state_machine_arn
          }
        }
      }
    ]
  })
}