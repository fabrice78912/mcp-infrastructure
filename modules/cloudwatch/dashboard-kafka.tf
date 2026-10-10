# Kafka Flow Monitoring Dashboard
resource "aws_cloudwatch_dashboard" "kafka_flow" {
  count = var.enable_alarms ? 1 : 0

  dashboard_name = "${var.environment}-${var.project_name}-kafka-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Header
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Kafka Flow Monitoring\n**Pipeline**: API Gateway → Step Functions → Kafka Producer → MSK → Kafka Consumer"
        }
      },

      # Kafka Consumer Invocations
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "FunctionName" = "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Messages Consumed"
          period  = 60
          stat    = "Sum"
        }
      },

      # Kafka Consumer Duration
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { "FunctionName" = "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Processing Duration"
          period  = 60
          stat    = "Average"
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
      },

      # Kafka Consumer Errors
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", { "FunctionName" = "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Errors"
          period  = 60
          stat    = "Sum"
        }
      },

      # Kafka Producer Invocations
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "FunctionName" = "${var.environment}-${var.project_name}-fcc_sender" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Producer - Messages Published"
          period  = 60
          stat    = "Sum"
        }
      },

      # Step Functions Executions
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted"],
            ["AWS/States", "ExecutionsSucceeded"],
            ["AWS/States", "ExecutionsFailed"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions - Executions"
          period  = 300
          stat    = "Sum"
        }
      },

      # Kafka Consumer Logs
      {
        type   = "log"
        x      = 0
        y      = 13
        width  = 24
        height = 6
        properties = {
          query   = <<-EOT
            SOURCE '/aws/lambda/${var.environment}-${var.project_name}-kafka_consumer'
            | fields @timestamp, @message
            | filter @message like /Kafka Message Received/
            | sort @timestamp desc
            | limit 20
          EOT
          region  = data.aws_region.current.name
          title   = "Recent Kafka Messages"
        }
      }
    ]
  })
}

output "kafka_dashboard_url" {
  description = "URL to the Kafka Flow CloudWatch Dashboard"
  value = var.enable_alarms ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.kafka_flow[0].dashboard_name}" : ""
}