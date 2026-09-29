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
      description = "IBM MQ credentials for dev"
      secret_data = {
        host     = var.ibm_mq_host
        port     = var.ibm_mq_port
        channel  = var.ibm_mq_channel
        password = var.ibm_mq_password
      }
    }
    mdmae = {
      description = "MDMAE service configuration for dev"
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

  environment                    = var.environment
  project_name                   = var.project_name
  table_name                     = "ClientProfile"
  enable_point_in_time_recovery  = var.enable_dynamodb_backup
  enable_encryption              = true
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
      message_retention_seconds  = 86400
      max_receive_count         = 3
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
  vpc_cidr     = "10.0.0.0/16"

  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
}

# ========================================
# MSK Serverless
# ========================================

module "msk" {
  source = "../../modules/msk"

  environment  = var.environment
  project_name = var.project_name

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  topics = {
    client_updates = {
      partitions = var.msk_partitions
    }
    fcc_responses = {
      partitions = var.msk_partitions
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
  secrets_arns       = module.secrets.secret_arns
}

# ========================================
# Lambda Functions
# ========================================

module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name
  aws_region   = var.aws_region

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn

  # Configuration Lambda
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # VPC configuration for MSK access
  vpc_subnet_ids         = module.vpc.private_subnet_ids
  vpc_security_group_ids = [module.vpc.lambda_security_group_id]

  # Environment variables
  dynamodb_table_name = module.dynamodb.table_name
  sqs_queue_url       = module.sqs.queue_urls["fcc_responses"]
  msk_bootstrap_servers = module.msk.bootstrap_servers

  # Secrets
  ibmmq_secret_arn = module.secrets.secret_arns["ibmmq"]
  mdmae_secret_arn = module.secrets.secret_arns["mdmae"]

  # Lambda functions to create
  functions = {
    client_profile_reader = {
      handler     = "com.bnc.mcp.orchestration.handlers.ClientProfileReader::handleRequest"
      description = "Read client profile from DynamoDB"
    }
    name_validator = {
      handler     = "com.bnc.mcp.orchestration.handlers.NameValidator::handleRequest"
      description = "Validate new client name"
    }
    mdmae_client = {
      handler     = "com.bnc.mcp.orchestration.handlers.MdmaeClient::handleRequest"
      description = "Call MDMAE service for duplicate detection"
    }
    fcc_sender = {
      handler     = "com.bnc.mcp.orchestration.handlers.FccSender::handleRequest"
      description = "Send update request to FCC via IBM MQ"
    }
    human_review_handler = {
      handler     = "com.bnc.mcp.orchestration.handlers.HumanReviewHandler::handleRequest"
      description = "Handle human review workflow"
    }
    mq_poller = {
      handler     = "com.bnc.mcp.fcc.connector.MqPoller::handleRequest"
      description = "Poll IBM MQ for FCC responses"
    }
    fcc_response_processor = {
      handler     = "com.bnc.mcp.fcc.connector.FccResponseProcessor::handleRequest"
      description = "Process FCC responses from SQS"
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

  rules = {
    mq_poller = {
      description         = "Poll IBM MQ every 10 seconds"
      schedule_expression = "rate(10 seconds)"
      lambda_function_arn = module.lambda.function_arns["mq_poller"]
    }
  }

  eventbridge_role_arn = module.iam.eventbridge_invoke_lambda_role_arn
}

# ========================================
# Step Functions
# ========================================

module "step_functions" {
  source = "../../modules/step-functions"

  environment  = var.environment
  project_name = var.project_name

  stepfunctions_role_arn = module.iam.stepfunctions_execution_role_arn
  dynamodb_table_name    = module.dynamodb.table_name

  state_machines = {
    client_name_update = {
      definition_template = "client-name-update.json.tpl"
      description         = "Client name update workflow"

      # Variables pour le template
      template_vars = {
        client_profile_reader_arn  = module.lambda.function_arns["client_profile_reader"]
        name_validator_arn         = module.lambda.function_arns["name_validator"]
        mdmae_client_arn           = module.lambda.function_arns["mdmae_client"]
        fcc_sender_arn             = module.lambda.function_arns["fcc_sender"]
        human_review_handler_arn   = module.lambda.function_arns["human_review_handler"]
        sqs_queue_url              = module.sqs.queue_urls["fcc_responses"]
        dynamodb_table_name        = module.dynamodb.table_name
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

  # Lambda API handler (will be created separately as Node.js function)
  api_lambda_function_arn = module.lambda.function_arns["client_profile_reader"] # Temporary placeholder

  # Throttling
  throttle_rate_limit  = var.api_throttle_rate_limit
  throttle_burst_limit = var.api_throttle_burst_limit

  # Step Functions
  state_machine_arn = module.step_functions.state_machine_arns["client_name_update"]
}

# ========================================
# CloudWatch (Logs & Alarms)
# ========================================

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment  = var.environment
  project_name = var.project_name

  # Logs retention
  log_retention_days = var.cloudwatch_retention_days

  # Lambda log groups
  lambda_function_names = keys(module.lambda.function_arns)

  # Alarms
  enable_alarms = var.enable_cloudwatch_alarms

  alarm_config = {
    lambda_error_threshold = 5
    lambda_duration_threshold = 30000
    dynamodb_error_threshold = 10
    stepfunctions_failure_threshold = 3
  }

  # Resources to monitor
  dynamodb_table_name    = module.dynamodb.table_name
  state_machine_arns     = values(module.step_functions.state_machine_arns)
  lambda_function_arns   = values(module.lambda.function_arns)
}