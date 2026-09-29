output "api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.arn
}

output "api_url" {
  description = "URL of the API Gateway"
  value       = "${aws_api_gateway_stage.main.invoke_url}/api/clients/{clientId}/nom"
}

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.main.stage_name
}

output "deployment_id" {
  description = "ID of the API Gateway deployment"
  value       = aws_api_gateway_deployment.main.id
}

output "swagger_ui_url" {
  description = "URL of the Swagger UI documentation"
  value       = "${aws_api_gateway_stage.main.invoke_url}/docs"
}

output "openapi_spec_url" {
  description = "URL of the OpenAPI specification (swagger.json)"
  value       = "${aws_api_gateway_stage.main.invoke_url}/swagger.json"
}