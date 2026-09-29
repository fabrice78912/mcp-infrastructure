resource "aws_msk_serverless_cluster" "main" {
  cluster_name = "${var.environment}-${var.project_name}-msk"

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-msk"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Note: Kafka topics are typically created by applications or Kafka admin tools
# This is a placeholder for documentation purposes
# In production, use terraform-provider-kafka or kafka-topics.sh to create topics