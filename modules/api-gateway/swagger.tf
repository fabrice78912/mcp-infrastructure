# Configuration Swagger UI pour l'API Gateway

# Lambda function pour servir Swagger UI
resource "aws_lambda_function" "swagger_ui" {
  function_name = "${var.environment}-${var.project_name}-swagger-ui"
  role          = var.lambda_execution_role_arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 10

  filename         = "${path.module}/swagger-ui-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/swagger-ui-lambda.zip")

  environment {
    variables = {
      API_GATEWAY_ID = aws_api_gateway_rest_api.main.id
      STAGE_NAME     = var.environment
    }
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-swagger-ui"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Log Group pour Swagger UI Lambda
resource "aws_cloudwatch_log_group" "swagger_ui" {
  name              = "/aws/lambda/${aws_lambda_function.swagger_ui.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-${var.project_name}-swagger-ui-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Permission pour API Gateway d'invoquer la Lambda Swagger UI
resource "aws_lambda_permission" "swagger_ui" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.swagger_ui.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*"
}

# /docs resource pour Swagger UI
resource "aws_api_gateway_resource" "docs" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "docs"
}

# GET /docs method
resource "aws_api_gateway_method" "get_docs" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.docs.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integration de /docs avec Lambda Swagger UI
resource "aws_api_gateway_integration" "get_docs" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.docs.id
  http_method = aws_api_gateway_method.get_docs.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.swagger_ui.invoke_arn
}

# /swagger.json resource pour la spec OpenAPI
resource "aws_api_gateway_resource" "swagger_json" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "swagger.json"
}

# GET /swagger.json method
resource "aws_api_gateway_method" "get_swagger_json" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.swagger_json.id
  http_method   = "GET"
  authorization = "NONE"
}

# Mock integration pour retourner la spec OpenAPI
resource "aws_api_gateway_integration" "get_swagger_json" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.swagger_json.id
  http_method = aws_api_gateway_method.get_swagger_json.http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response pour /swagger.json
resource "aws_api_gateway_method_response" "get_swagger_json_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.swagger_json.id
  http_method = aws_api_gateway_method.get_swagger_json.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Type"                = true
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response avec la spec OpenAPI
resource "aws_api_gateway_integration_response" "get_swagger_json" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.swagger_json.id
  http_method = aws_api_gateway_method.get_swagger_json.http_method
  status_code = aws_api_gateway_method_response.get_swagger_json_200.status_code

  response_parameters = {
    "method.response.header.Content-Type"                = "'application/json'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = templatefile("${path.module}/openapi-spec.json.tpl", {
      api_id      = aws_api_gateway_rest_api.main.id
      environment = var.environment
      region      = data.aws_region.current.name
    })
  }

  depends_on = [aws_api_gateway_integration.get_swagger_json]
}