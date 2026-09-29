# ========================================
# Data sources
# ========================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source for Lambda artifacts bucket (created by bootstrap)
# Using data source instead of remote state for GitHub Actions compatibility
data "aws_s3_bucket" "lambda_artifacts" {
  bucket = "bnc-mcp-lambda-artifacts"
}

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

# Phone Update workflow tables
module "dynamodb_phone_history" {
  source = "../../modules/dynamodb"

  environment                    = var.environment
  project_name                   = var.project_name
  table_name                     = "PhoneNumberHistory"
  enable_point_in_time_recovery  = var.enable_dynamodb_backup
  enable_encryption              = true
}

module "dynamodb_otp_codes" {
  source = "../../modules/dynamodb"

  environment                    = var.environment
  project_name                   = var.project_name
  table_name                     = "OTPCodes"
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
    fraud_review = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 86400
      max_receive_count         = 3
    }
  }
}

# ========================================
# SNS
# ========================================

module "sns" {
  source = "../../modules/sns"

  environment  = var.environment
  project_name = var.project_name

  topics = {
    otp_sms = {
      display_name = "OTP SMS notifications"
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
  aws_account_id     = data.aws_caller_identity.current.account_id

  # Main resources
  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arns["fcc_responses"]
  msk_cluster_arn    = module.msk.cluster_arn
  secrets_arns       = values(module.secrets.secret_arns)

  # Phone Update workflow resources
  phone_history_table_arn = module.dynamodb_phone_history.table_arn
  otp_codes_table_arn     = module.dynamodb_otp_codes.table_arn
  fraud_review_queue_arn  = module.sqs.queue_arns["fraud_review"]
  sns_topic_arn           = module.sns.topic_arns["otp_sms"]

  # State machine ARN will be set after Step Functions module is created
  # For now, we'll use an empty string since it's optional
  phone_update_state_machine_arn = ""
}

# ========================================
# Lambda Functions
# ========================================

module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn

  # Lambda code bucket
  lambda_code_bucket = data.aws_s3_bucket.lambda_artifacts.bucket
  code_version       = var.code_version

  # DynamoDB table names
  dynamodb_client_table_name       = module.dynamodb.table_name
  dynamodb_phone_history_table_name = module.dynamodb_phone_history.table_name
  dynamodb_otp_table_name          = module.dynamodb_otp_codes.table_name

  # SQS queue URLs
  sqs_fraud_review_queue_url = module.sqs.queue_urls["fraud_review"]

  # API endpoints
  mdmae_api_endpoint = var.mdmae_url
  fcc_api_endpoint   = "https://fcc-api-dev.example.com"  # TODO: Update with real endpoint
  crm_api_endpoint   = "https://crm-api-dev.example.com"  # TODO: Update with real endpoint

  # SNS topic ARN
  sns_topic_arn = module.sns.topic_arns["otp_sms"]

  # API Gateway execution ARN (to be set after API Gateway is created)
  api_gateway_execution_arn = "${module.api_gateway.api_arn}/*"

  # Step Functions ARN (to be set after Step Functions is created)
  step_functions_phone_update_arn = module.step_functions.state_machine_arns["client_name_update"]

  # Lambda functions to create
  functions = {
    client_profile_reader = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "validationHandler"
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        AWS_REGION                       = var.aws_region
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    name_validator = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "matchingHandler"
        MDMAE_API_ENDPOINT               = var.mdmae_url
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        AWS_REGION                       = var.aws_region
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    mdmae_client = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "updateProfileHandler"
        MDMAE_API_ENDPOINT               = var.mdmae_url
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        AWS_REGION                       = var.aws_region
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    fcc_sender = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "publishEventHandler"
        IBM_MQ_SECRET_ARN                = module.secrets.secret_arns["ibmmq"]
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        AWS_REGION                       = var.aws_region
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    human_review_handler = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "humanReviewHandler"
        FRAUD_REVIEW_QUEUE_URL           = module.sqs.queue_urls["fraud_review"]
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        AWS_REGION                       = var.aws_region
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    mq_poller = {
      handler     = "com.bnc.mcp.fcc.connector.MqPoller::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        IBM_MQ_SECRET_ARN = module.secrets.secret_arns["ibmmq"]
        SQS_QUEUE_URL     = module.sqs.queue_urls["fcc_responses"]
        LOG_LEVEL         = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
    fcc_response_processor = {
      handler     = "com.bnc.mcp.fcc.connector.FccResponseProcessor::handleRequest"
      runtime     = "java17"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        DYNAMODB_TABLE = module.dynamodb.table_name
        LOG_LEVEL      = "INFO"
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

  rules = {
    mq_poller = {
      description         = "Poll IBM MQ every 1 minute"
      schedule_expression = "rate(1 minute)"
      target_lambda_arn   = module.lambda.function_arns["mq_poller"]
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

  state_machines = {
    client_name_update = {
      definition_template = "client-name-update.json.tpl"
      role_arn           = module.iam.stepfunctions_execution_role_arn

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

  # CloudWatch logging
  cloudwatch_role_arn = module.iam.api_gateway_cloudwatch_role_arn

  # Throttling
  throttle_rate_limit  = var.api_throttle_rate_limit
  throttle_burst_limit = var.api_throttle_burst_limit

  # Step Functions
  state_machine_arn = module.step_functions.state_machine_arns["client_name_update"]

  # Phone Update workflow Lambda functions (optional - leave empty for now)
  phone_update_controller_invoke_arn = ""
  phone_update_controller_arn        = ""
  phone_update_status_checker_arn    = ""
}

# ========================================
# CloudWatch (Logs & Alarms)
# ========================================

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment  = var.environment
  project_name = var.project_name

  # Lambda log groups (as map)
  lambda_function_names = module.lambda.function_arns

  # Step Functions monitoring
  state_machine_arns = module.step_functions.state_machine_arns

  # Alarms configuration
  enable_alarms          = var.enable_cloudwatch_alarms
  error_threshold        = 5
  duration_threshold_ms  = 30000
}