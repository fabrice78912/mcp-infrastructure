# IAM Policies for Phone Update Workflow

# Additional Lambda policy for phone update specific resources
resource "aws_iam_role_policy" "lambda_phone_update_permissions" {
  name = "${var.environment}-${var.project_name}-lambda-phone-update-permissions"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Access to phone update specific DynamoDB tables
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          var.phone_history_table_arn,
          var.otp_codes_table_arn,
          "${var.otp_codes_table_arn}/index/*"
        ]
      },
      # Access to fraud review SQS queue
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.fraud_review_queue_arn
      },
      # SNS for sending OTP SMS
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      # Step Functions - send task success/failure for human approval
      {
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure",
          "states:SendTaskHeartbeat"
        ]
        Resource = var.phone_update_state_machine_arn
      }
    ]
  })
}

# Additional Step Functions policy for phone update specific resources
resource "aws_iam_role_policy" "stepfunctions_phone_update_permissions" {
  name = "${var.environment}-${var.project_name}-stepfunctions-phone-update-permissions"
  role = aws_iam_role.stepfunctions_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Access to phone update specific DynamoDB tables
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          var.phone_history_table_arn,
          var.otp_codes_table_arn
        ]
      },
      # Send messages to fraud review queue
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = var.fraud_review_queue_arn
      },
      # Invoke all phone update Lambda functions
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-phone-update-controller",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-read-client-profile",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-phone-validator",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-check-phone-history",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-human-approval-handler",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-send-otp-sms",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-check-otp-status",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-phone-mdmae-client",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-fcc-sender-phone",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-crm-updater-phone",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-notification-updater-phone"
        ]
      }
    ]
  })
}

# SNS Topic Policy to allow Lambda to publish
resource "aws_sns_topic_policy" "otp_sms_policy" {
  arn = var.sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = var.sns_topic_arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}