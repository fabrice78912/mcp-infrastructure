# Lambda Functions for Phone Update Workflow

locals {
  phone_update_functions = {
    # Controller Lambda - Entry point from API Gateway
    "phone-update-controller" = {
      handler       = "com.bnc.mcp.controllers.ClientPhoneUpdateController::handleRequest"
      runtime       = "java17"
      memory_size   = 512
      timeout       = 30
      s3_key        = "phone-update/client-phone-update-controller-${var.code_version}.jar"
      trigger_type  = "api_gateway"
    }

    # Read client profile
    "read-client-profile" = {
      handler       = "com.bnc.mcp.handlers.ReadClientProfileHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 10
      s3_key        = "phone-update/read-client-profile-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Phone validator - validates format, type, carrier
    "phone-validator" = {
      handler       = "com.bnc.mcp.handlers.PhoneValidatorHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 10
      s3_key        = "phone-update/phone-validator-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Check phone history - fraud detection
    "check-phone-history" = {
      handler       = "com.bnc.mcp.handlers.CheckPhoneHistoryHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 15
      s3_key        = "phone-update/check-phone-history-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Human approval handler
    "human-approval-handler" = {
      handler       = "com.bnc.mcp.handlers.HumanApprovalHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 10
      s3_key        = "phone-update/human-approval-handler-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Send OTP SMS
    "send-otp-sms" = {
      handler       = "com.bnc.mcp.handlers.SendOTPSMSHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 15
      s3_key        = "phone-update/send-otp-sms-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Check OTP status
    "check-otp-status" = {
      handler       = "com.bnc.mcp.handlers.CheckOTPStatusHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 10
      s3_key        = "phone-update/check-otp-status-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # MDMAE client - update master system
    "phone-mdmae-client" = {
      handler       = "com.bnc.mcp.handlers.PhoneMDMAEClientHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 512
      timeout       = 30
      s3_key        = "phone-update/phone-mdmae-client-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # FCC sender - send to FCC system
    "fcc-sender-phone" = {
      handler       = "com.bnc.mcp.handlers.FCCSenderHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 20
      s3_key        = "phone-update/fcc-sender-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # CRM updater
    "crm-updater-phone" = {
      handler       = "com.bnc.mcp.handlers.CRMUpdaterHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 15
      s3_key        = "phone-update/crm-updater-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }

    # Notification service updater
    "notification-updater-phone" = {
      handler       = "com.bnc.mcp.handlers.NotificationUpdaterHandler::handleRequest"
      runtime       = "java17"
      memory_size   = 256
      timeout       = 15
      s3_key        = "phone-update/notification-updater-${var.code_version}.jar"
      trigger_type  = "step_functions"
    }
  }
}

# Create Lambda functions for phone update workflow
resource "aws_lambda_function" "phone_update_functions" {
  for_each = local.phone_update_functions

  function_name = "${var.environment}-mcp-${each.key}"
  role          = var.lambda_execution_role_arn

  # S3 deployment package
  s3_bucket = var.lambda_code_bucket
  s3_key    = each.value.s3_key

  # Runtime configuration
  handler       = each.value.handler
  runtime       = each.value.runtime
  memory_size   = each.value.memory_size
  timeout       = each.value.timeout
  architectures = ["arm64"]

  # Environment variables
  environment {
    variables = {
      ENVIRONMENT                = var.environment
      DYNAMODB_CLIENT_TABLE      = var.dynamodb_client_table_name
      DYNAMODB_PHONE_HISTORY     = var.dynamodb_phone_history_table_name
      DYNAMODB_OTP_TABLE         = var.dynamodb_otp_table_name
      SQS_FRAUD_REVIEW_QUEUE_URL = var.sqs_fraud_review_queue_url
      MDMAE_API_ENDPOINT         = var.mdmae_api_endpoint
      FCC_API_ENDPOINT           = var.fcc_api_endpoint
      CRM_API_ENDPOINT           = var.crm_api_endpoint
      SNS_TOPIC_ARN              = var.sns_topic_arn
      LOG_LEVEL                  = var.log_level
    }
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  tags = {
    Name        = "${var.environment}-mcp-${each.key}"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workflow    = "phone-update"
    Function    = each.key
  }

  depends_on = [aws_cloudwatch_log_group.phone_update_lambda_logs]
}

# CloudWatch Log Groups for phone update Lambdas
resource "aws_cloudwatch_log_group" "phone_update_lambda_logs" {
  for_each = local.phone_update_functions

  name              = "/aws/lambda/${var.environment}-mcp-${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-mcp-${each.key}-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workflow    = "phone-update"
  }
}

# Lambda permissions for API Gateway (controller only)
resource "aws_lambda_permission" "phone_update_api_gateway" {
  for_each = {
    for k, v in local.phone_update_functions : k => v
    if v.trigger_type == "api_gateway"
  }

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.phone_update_functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

# Lambda permissions for Step Functions
resource "aws_lambda_permission" "phone_update_step_functions" {
  for_each = {
    for k, v in local.phone_update_functions : k => v
    if v.trigger_type == "step_functions"
  }

  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.phone_update_functions[each.key].function_name
  principal     = "states.amazonaws.com"
  source_arn    = var.step_functions_phone_update_arn
}