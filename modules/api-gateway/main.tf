resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.environment}-${var.project_name}-api"
  description = "MCP Client Name Update API for ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# /api resource
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "api"
}

# /api/clients resource
resource "aws_api_gateway_resource" "clients" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "clients"
}

# /api/clients/{clientId} resource
resource "aws_api_gateway_resource" "client_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.clients.id
  path_part   = "{clientId}"
}

# /api/clients/{clientId}/nom resource
resource "aws_api_gateway_resource" "nom" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "nom"
}

# PUT /api/clients/{clientId}/nom method
resource "aws_api_gateway_method" "put_nom" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.nom.id
  http_method   = "PUT"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.clientId" = true
  }
}

# Integration with Step Functions
resource "aws_api_gateway_integration" "stepfunctions" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials             = aws_iam_role.api_stepfunctions.arn

  request_templates = {
    "application/json" = <<EOF
{
  "stateMachineArn": "${var.state_machine_arn}",
  "input": "{\"clientId\": \"$util.escapeJavaScript($input.params('clientId'))\", \"newLastName\": \"$util.escapeJavaScript($input.path('$.newLastName'))\", \"reason\": \"$util.escapeJavaScript($input.path('$.reason'))\"}"
}
EOF
  }

  passthrough_behavior = "NEVER"
}

# Method response
resource "aws_api_gateway_method_response" "put_nom_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response
resource "aws_api_gateway_integration_response" "stepfunctions" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method
  status_code = aws_api_gateway_method_response.put_nom_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Client name update initiated",
  "executionArn": $input.json('$.executionArn')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.stepfunctions]
}

# Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.stepfunctions,
    aws_api_gateway_integration_response.stepfunctions,
    aws_api_gateway_method_response.put_nom_200,
    aws_api_gateway_integration.get_docs,
    aws_api_gateway_integration_response.get_swagger_json
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.nom.id,
      aws_api_gateway_method.put_nom.id,
      aws_api_gateway_integration.stepfunctions.id,
      aws_api_gateway_integration_response.stepfunctions.id,
    ]))
  }
}

# Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.environment}-${var.project_name}-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-${var.project_name}-api-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Method Settings (throttling)
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit
  }
}

# IAM Role for API Gateway to invoke Step Functions
resource "aws_iam_role" "api_stepfunctions" {
  name = "${var.environment}-${var.project_name}-api-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-${var.project_name}-api-sfn-role"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "api_stepfunctions" {
  name = "StepFunctionsInvoke"
  role = aws_iam_role.api_stepfunctions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution",
          "states:StartSyncExecution"
        ]
        Resource = var.state_machine_arn
      }
    ]
  })
}

# API Gateway account (for CloudWatch logging)
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = var.cloudwatch_role_arn
}

data "aws_region" "current" {}