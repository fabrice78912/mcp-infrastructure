# ========================================
# Swagger/OpenAPI Documentation
# ========================================

# Bucket S3 pour héberger la documentation Swagger
resource "aws_s3_bucket" "swagger_docs" {
  bucket = "${var.environment}-mcp-api-docs"

  tags = {
    Name        = "${var.environment}-mcp-api-docs"
    Environment = var.environment
    Project     = "MCP"
    Purpose     = "Swagger Documentation"
  }
}

# Configuration publique pour le bucket (lecture seule)
resource "aws_s3_bucket_public_access_block" "swagger_docs" {
  bucket = aws_s3_bucket.swagger_docs.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Policy pour permettre la lecture publique
resource "aws_s3_bucket_policy" "swagger_docs_public_read" {
  bucket = aws_s3_bucket.swagger_docs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.swagger_docs.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.swagger_docs]
}

# Configuration du bucket pour hébergement web
resource "aws_s3_bucket_website_configuration" "swagger_docs" {
  bucket = aws_s3_bucket.swagger_docs.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Upload du fichier OpenAPI spec
resource "aws_s3_object" "openapi_spec" {
  bucket       = aws_s3_bucket.swagger_docs.id
  key          = "phone-update/openapi.yaml"
  content      = templatefile("${path.module}/../../openapi/phone-update-api.yaml", {
    phone_update_controller_arn     = var.phone_update_controller_arn
    phone_update_status_checker_arn = var.phone_update_status_checker_arn
  })
  content_type = "application/x-yaml"
  etag         = filemd5("${path.module}/../../openapi/phone-update-api.yaml")

  tags = {
    Name = "phone-update-openapi-spec"
  }
}

# Upload du fichier OpenAPI spec en JSON (pour compatibilité)
resource "aws_s3_object" "openapi_spec_json" {
  bucket       = aws_s3_bucket.swagger_docs.id
  key          = "phone-update/openapi.json"
  content      = templatefile("${path.module}/../../openapi/phone-update-api.yaml", {
    phone_update_controller_arn     = var.phone_update_controller_arn
    phone_update_status_checker_arn = var.phone_update_status_checker_arn
  })
  content_type = "application/json"

  tags = {
    Name = "phone-update-openapi-spec-json"
  }
}

# Upload de Swagger UI (fichiers HTML/CSS/JS)
# Note: Ces fichiers doivent être téléchargés depuis https://github.com/swagger-api/swagger-ui/releases
resource "aws_s3_object" "swagger_ui_index" {
  bucket = aws_s3_bucket.swagger_docs.id
  key    = "phone-update/index.html"
  content = templatefile("${path.module}/swagger-ui/index.html", {
    openapi_spec_url = "https://${aws_s3_bucket.swagger_docs.id}.s3.ca-central-1.amazonaws.com/phone-update/openapi.yaml"
  })
  content_type = "text/html"

  tags = {
    Name = "swagger-ui-index"
  }
}

# CloudFront distribution pour servir Swagger UI (optionnel mais recommandé)
resource "aws_cloudfront_distribution" "swagger_docs" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.environment} MCP API Documentation"
  default_root_object = "phone-update/index.html"

  origin {
    domain_name = aws_s3_bucket_website_configuration.swagger_docs.website_endpoint
    origin_id   = "S3-swagger-docs"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-swagger-docs"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.environment}-mcp-swagger-cdn"
    Environment = var.environment
  }
}

# API Gateway Documentation
resource "aws_api_gateway_documentation_version" "phone_update" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  version     = var.api_version
  description = "Phone Update API Documentation v${var.api_version}"

  depends_on = [
    aws_api_gateway_method.put_phone,
    aws_api_gateway_integration.phone_lambda
  ]
}

# Export de la spec OpenAPI depuis API Gateway (alternatif)
resource "aws_api_gateway_stage" "main" {
  deployment_id        = aws_api_gateway_deployment.main.id
  rest_api_id          = aws_api_gateway_rest_api.main.id
  stage_name           = var.environment
  description          = "${var.environment} stage with OpenAPI documentation"

  # Activer les logs CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
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
    Name        = "${var.environment}-api-stage"
    Environment = var.environment
  }
}

# Log group pour API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.environment}-mcp-api"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-api-gateway-logs"
    Environment = var.environment
  }
}

# ========================================
# Outputs
# ========================================

output "swagger_ui_url" {
  description = "URL de la documentation Swagger UI"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.swagger_docs[0].domain_name}/phone-update/index.html" : "http://${aws_s3_bucket_website_configuration.swagger_docs.website_endpoint}/phone-update/index.html"
}

output "openapi_spec_url" {
  description = "URL de la spécification OpenAPI (YAML)"
  value       = "https://${aws_s3_bucket.swagger_docs.id}.s3.ca-central-1.amazonaws.com/phone-update/openapi.yaml"
}

output "openapi_spec_json_url" {
  description = "URL de la spécification OpenAPI (JSON)"
  value       = "https://${aws_s3_bucket.swagger_docs.id}.s3.ca-central-1.amazonaws.com/phone-update/openapi.json"
}

output "api_gateway_stage_url" {
  description = "URL de l'API Gateway stage"
  value       = "${aws_api_gateway_stage.main.invoke_url}"
}