# API Gateway endpoint for Phone Update Workflow

# /api/clients/{clientId}/phone resource
resource "aws_api_gateway_resource" "phone" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "phone"
}

# PUT /api/clients/{clientId}/phone method
resource "aws_api_gateway_method" "put_phone" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.phone.id
  http_method   = "PUT"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.clientId" = true
  }

  request_validator_id = aws_api_gateway_request_validator.phone_update.id
}

# Request validator for phone update
resource "aws_api_gateway_request_validator" "phone_update" {
  name                        = "${var.environment}-phone-update-validator"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = true
  validate_request_parameters = true
}

# Request model for phone update
resource "aws_api_gateway_model" "phone_update_request" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "PhoneUpdateRequest"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Phone Update Request"
    type      = "object"
    required  = ["phoneNumber", "country"]
    properties = {
      phoneNumber = {
        type        = "string"
        description = "New phone number in E.164 format (e.g., +15141234567)"
        pattern     = "^\\+[1-9]\\d{1,14}$"
      }
      country = {
        type        = "string"
        description = "Country code (ISO 3166-1 alpha-2, e.g., CA, US)"
        pattern     = "^[A-Z]{2}$"
      }
    }
  })
}

# Integration with Lambda Controller (not Step Functions directly)
resource "aws_api_gateway_integration" "phone_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.put_phone.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.phone_update_controller_invoke_arn

  passthrough_behavior = "WHEN_NO_MATCH"
}

# Method response - 200 OK
resource "aws_api_gateway_method_response" "put_phone_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.put_phone.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Method response - 400 Bad Request
resource "aws_api_gateway_method_response" "put_phone_400" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.put_phone.http_method
  status_code = "400"

  response_models = {
    "application/json" = "Error"
  }
}

# Method response - 500 Internal Server Error
resource "aws_api_gateway_method_response" "put_phone_500" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.put_phone.http_method
  status_code = "500"

  response_models = {
    "application/json" = "Error"
  }
}

# CORS - OPTIONS method for /phone
resource "aws_api_gateway_method" "options_phone" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.phone.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS - OPTIONS integration
resource "aws_api_gateway_integration" "options_phone" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.options_phone.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS - OPTIONS method response
resource "aws_api_gateway_method_response" "options_phone_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.options_phone.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# CORS - OPTIONS integration response
resource "aws_api_gateway_integration_response" "options_phone" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.options_phone.http_method
  status_code = aws_api_gateway_method_response.options_phone_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options_phone]
}

# Update deployment to include phone endpoint
resource "aws_api_gateway_deployment" "phone_update" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.phone_lambda,
    aws_api_gateway_integration.options_phone
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.phone.id,
      aws_api_gateway_method.put_phone.id,
      aws_api_gateway_integration.phone_lambda.id,
      aws_api_gateway_method.options_phone.id,
    ]))
  }
}