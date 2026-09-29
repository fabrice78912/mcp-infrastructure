# ========================================
# Data sources
# ========================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ========================================
# Secrets Manager
# ========================================

module "secrets" {
  source = "../../modules/secrets-manager"

  environment  = var.environment
  project_name = var.project_name

  secrets = {
    ibmmq = {
      description = "IBM MQ credentials for prod"
      secret_data = {
        host     = var.ibm_mq_host
        port     = var.ibm_mq_port
        channel  = var.ibm_mq_channel
        password = var.ibm_mq_password
      }
    }
    mdmae = {
      description = "MDMAE service configuration for prod"
      secret_data = {
        url = var.mdmae_url
      }
    }
  }
}

# ========================================
# DynamoDB
# ========================================

module "dynamodb" {
  source = "../../modules/dynamodb"

  environment                   = var.environment
  project_name                  = var.project_name
  table_name                    = "ClientProfile"
  enable_point_in_time_recovery = var.enable_dynamodb_backup
  enable_encryption             = true
}

# ========================================
# SQS
# ========================================

module "sqs" {
  source = "../../modules/sqs"

  environment  = var.environment
  project_name = var.project_name

  queues = {
    fcc_responses = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 345600 # 4 days for prod
      max_receive_count          = 3
    }
  }
}

# ========================================
# VPC (for MSK)
# ========================================

module "vpc" {
  source = "../../modules/vpc"

  environment  = var.environment
  project_name = var.project_name
  vpc_cidr     = "10.1.0.0/16" # Different CIDR for prod

  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  enable_vpc_endpoints = true # Enable for better performance in prod
}

# ========================================
# MSK Serverless
# ========================================

module "msk" {
  source = "../../modules/msk"

  environment  = var.environment
  project_name = var.project_name

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.vpc.msk_security_group_id]

  kafka_topics = {
    client_updates = {
      partitions         = var.msk_partitions
      replication_factor = 2
    }
    fcc_responses = {
      partitions         = var.msk_partitions
      replication_factor = 2
    }
  }
}

# ========================================
# IAM
# ========================================

module "iam" {
  source = "../../modules/iam"

  environment        = var.environment
  project_name       = var.project_name
  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arns["fcc_responses"]
  msk_cluster_arn    = module.msk.cluster_arn
  secrets_arns       = values(module.secrets.secret_arns)
}

# ========================================
# Lambda Functions
# ========================================

module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  log_retention_days        = var.cloudwatch_retention_days

  functions = {
    client-profile-reader = {
      handler     = "com.bnc.mcp.api.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        DYNAMODB_TABLE_NAME = module.dynamodb.table_name
        SECRETS_ARN_IBMMQ   = module.secrets.secret_arns["ibmmq"]
        SECRETS_ARN_MDMAE   = module.secrets.secret_arns["mdmae"]
        ENVIRONMENT         = var.environment
      }
      vpc_config = null
    }
    name-validator = {
      handler     = "com.bnc.mcp.orchestration.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        DYNAMODB_TABLE_NAME = module.dynamodb.table_name
        ENVIRONMENT         = var.environment
      }
      vpc_config = null
    }
    mdmae-client = {
      handler     = "com.bnc.mcp.orchestration.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SECRETS_ARN_MDMAE = module.secrets.secret_arns["mdmae"]
        ENVIRONMENT       = var.environment
      }
      vpc_config = null
    }
    fcc-sender = {
      handler     = "com.bnc.mcp.fcc.connector.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SECRETS_ARN_IBMMQ = module.secrets.secret_arns["ibmmq"]
        ENVIRONMENT       = var.environment
      }
      vpc_config = null
    }
    human-review-handler = {
      handler     = "com.bnc.mcp.orchestration.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        DYNAMODB_TABLE_NAME = module.dynamodb.table_name
        ENVIRONMENT         = var.environment
      }
      vpc_config = null
    }
    mq-poller = {
      handler     = "com.bnc.mcp.fcc.connector.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SECRETS_ARN_IBMMQ = module.secrets.secret_arns["ibmmq"]
        SQS_QUEUE_URL     = module.sqs.queue_urls["fcc_responses"]
        ENVIRONMENT       = var.environment
      }
      vpc_config = null
    }
    fcc-response-processor = {
      handler     = "com.bnc.mcp.fcc.connector.LambdaHandler::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        DYNAMODB_TABLE_NAME   = module.dynamodb.table_name
        MSK_BOOTSTRAP_SERVERS = module.msk.bootstrap_brokers
        ENVIRONMENT           = var.environment
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
  }
}

# ========================================
# EventBridge (MQ Polling Schedule)
# ========================================

module "eventbridge" {
  source = "../../modules/eventbridge"

  environment  = var.environment
  project_name = var.project_name

  eventbridge_role_arn = module.iam.eventbridge_invoke_lambda_role_arn

  rules = {
    mq-poller = {
      description         = "Poll IBM MQ every 10 seconds"
      schedule_expression = "rate(10 seconds)"
      target_lambda_arn   = module.lambda.function_arns["mq-poller"]
    }
  }
}

# ========================================
# Step Functions
# ========================================

module "step_functions" {
  source = "../../modules/step-functions"

  environment  = var.environment
  project_name = var.project_name

  log_retention_days = var.cloudwatch_retention_days

  state_machines = {
    client-name-update = {
      definition_template = "state-machines/client-name-update.json.tpl"
      role_arn            = module.iam.stepfunctions_execution_role_arn
      template_vars = {
        client_profile_reader_arn = module.lambda.function_arns["client-profile-reader"]
        name_validator_arn        = module.lambda.function_arns["name-validator"]
        mdmae_client_arn          = module.lambda.function_arns["mdmae-client"]
        fcc_sender_arn            = module.lambda.function_arns["fcc-sender"]
        human_review_handler_arn  = module.lambda.function_arns["human-review-handler"]
        dynamodb_table_name       = module.dynamodb.table_name
      }
    }
  }
}

# ========================================
# API Gateway
# ========================================

module "api_gateway" {
  source = "../../modules/api-gateway"

  environment  = var.environment
  project_name = var.project_name

  state_machine_arn    = module.step_functions.state_machine_arns["client-name-update"]
  cloudwatch_role_arn  = module.iam.api_gateway_cloudwatch_role_arn
  log_retention_days   = var.cloudwatch_retention_days
  throttle_rate_limit  = var.api_throttle_rate_limit
  throttle_burst_limit = var.api_throttle_burst_limit
}

# ========================================
# CloudWatch (Logs & Alarms)
# ========================================

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment  = var.environment
  project_name = var.project_name

  enable_alarms         = var.enable_cloudwatch_alarms
  lambda_function_names = module.lambda.function_names
  state_machine_arns    = module.step_functions.state_machine_arns
  api_gateway_name      = "${var.environment}-${var.project_name}-api"
  alarm_email           = var.alarm_email

  error_threshold        = 10
  duration_threshold_ms  = 10000 # 10 seconds for prod
}