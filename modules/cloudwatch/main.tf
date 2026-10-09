# SNS Topic for alarms (optional)
resource "aws_sns_topic" "alarms" {
  count = var.enable_alarms && var.alarm_email != "" ? 1 : 0

  name = "${var.environment}-${var.project_name}-alarms"

  tags = {
    Name        = "${var.environment}-${var.project_name}-alarms"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.enable_alarms && var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Lambda Error Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.enable_alarms ? var.lambda_function_names : {}

  alarm_name          = "${var.environment}-${var.project_name}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "Lambda function ${each.value} error count exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-errors"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Lambda Duration Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.enable_alarms ? var.lambda_function_names : {}

  alarm_name          = "${var.environment}-${var.project_name}-${each.key}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = var.duration_threshold_ms
  alarm_description   = "Lambda function ${each.value} duration exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-duration"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Lambda Throttles Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.enable_alarms ? var.lambda_function_names : {}

  alarm_name          = "${var.environment}-${var.project_name}-${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda function ${each.value} is being throttled"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-throttles"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Step Functions Failed Executions Alarms
resource "aws_cloudwatch_metric_alarm" "stepfunctions_failed" {
  for_each = var.enable_alarms ? var.state_machine_arns : {}

  alarm_name          = "${var.environment}-${var.project_name}-${each.key}-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Step Functions ${each.key} has failed executions"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = each.value
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}-failed"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# API Gateway 5XX Errors Alarm
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  count = var.enable_alarms && var.api_gateway_name != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway has high 5XX error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-api-5xx-errors"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# API Gateway Latency Alarm
resource "aws_cloudwatch_metric_alarm" "api_gateway_latency" {
  count = var.enable_alarms && var.api_gateway_name != "" ? 1 : 0

  alarm_name          = "${var.environment}-${var.project_name}-api-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 5000 # 5 seconds
  alarm_description   = "API Gateway latency is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name        = "${var.environment}-${var.project_name}-api-latency"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Dashboard - Kafka Flow Monitoring
resource "aws_cloudwatch_dashboard" "main" {
  count = var.enable_alarms ? 1 : 0

  dashboard_name = "${var.environment}-${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ========================================
      # SECTION 1: Kafka Flow Overview
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# 📊 MCP Kafka Flow Dashboard\n**End-to-End Monitoring**: API Gateway → Step Functions → Kafka Producer → MSK → Kafka Consumer"
        }
      },

      # ========================================
      # SECTION 2: Kafka Consumer Metrics
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 1
        width  = 24
        height = 1
        properties = {
          markdown = "## 🔄 Kafka Consumer (kafka_consumer Lambda)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "stat" : "Sum", "label" : "Messages Consumed", "color" : "#1f77b4" }, { "FunctionName" : "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Message Consumption Rate"
          period  = 60
          yAxis = {
            left = {
              label = "Messages"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { "stat" : "Average", "label" : "Avg Duration", "color" : "#ff7f0e" }, { "FunctionName" : "${var.environment}-${var.project_name}-kafka_consumer" }],
            ["...", { "stat" : "Maximum", "label" : "Max Duration", "color" : "#d62728" }],
            ["...", { "stat" : "Minimum", "label" : "Min Duration", "color" : "#2ca02c" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Processing Duration"
          period  = 60
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", { "stat" : "Sum", "label" : "Errors", "color" : "#d62728" }, { "FunctionName" : "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Errors"
          period  = 60
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", { "stat" : "Maximum", "label" : "Concurrent Executions", "color" : "#9467bd" }, { "FunctionName" : "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Concurrency"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Throttles", { "stat" : "Sum", "label" : "Throttles", "color" : "#e377c2" }, { "FunctionName" : "${var.environment}-${var.project_name}-kafka_consumer" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Throttles"
          period  = 60
        }
      },

      # ========================================
      # SECTION 3: Kafka Producer (fcc_sender Lambda)
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = {
          markdown = "## 📤 Kafka Producer (fcc_sender Lambda)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "stat" : "Sum", "label" : "Messages Published", "color" : "#2ca02c" }, { "FunctionName" : "${var.environment}-${var.project_name}-fcc_sender" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Producer - Message Publishing Rate"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 15
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { "stat" : "Average", "label" : "Avg Publish Duration", "color" : "#ff7f0e" }, { "FunctionName" : "${var.environment}-${var.project_name}-fcc_sender" }],
            ["AWS/Lambda", "Errors", { "stat" : "Sum", "label" : "Publishing Errors", "color" : "#d62728" }, { "FunctionName" : "${var.environment}-${var.project_name}-fcc_sender" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kafka Producer - Performance & Errors"
          period  = 60
        }
      },

      # ========================================
      # SECTION 4: Step Functions Workflow
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 21
        width  = 24
        height = 1
        properties = {
          markdown = "## 🔁 Step Functions Workflow (client_name_update)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 22
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted", { stat = "Sum", label = "Started", color = "#1f77b4" }],
            ["...", "ExecutionsSucceeded", { stat = "Sum", label = "Succeeded", color = "#2ca02c" }],
            ["...", "ExecutionsFailed", { stat = "Sum", label = "Failed", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions - Execution Status"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 22
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionTime", { stat = "Average", label = "Avg Duration", color = "#ff7f0e" }],
            ["...", { stat = "Maximum", label = "Max Duration", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions - Execution Duration"
          period  = 300
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 22
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionThrottled", { stat = "Sum", label = "Throttled", color = "#e377c2" }],
            ["...", "ExecutionsTimedOut", { stat = "Sum", label = "Timed Out", color = "#bcbd22" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions - Issues"
          period  = 300
        }
      },

      # ========================================
      # SECTION 5: API Gateway
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 28
        width  = 24
        height = 1
        properties = {
          markdown = "## 🌐 API Gateway (Entry Point)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 29
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum", label = "Total Requests", color = "#1f77b4" }],
            ["...", "4XXError", { stat = "Sum", label = "4XX Errors", color = "#ff7f0e" }],
            ["...", "5XXError", { stat = "Sum", label = "5XX Errors", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway - Request Volume & Errors"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 29
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", { stat = "Average", label = "Avg Latency", color = "#ff7f0e" }],
            ["...", { stat = "p99", label = "P99 Latency", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway - Latency"
          period  = 300
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
      },

      # ========================================
      # SECTION 6: All Lambda Functions Overview
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 35
        width  = 24
        height = 1
        properties = {
          markdown = "## 🔧 All Lambda Functions"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 36
        width  = 12
        height = 6
        properties = {
          metrics = [
            for name, arn in var.lambda_function_names : [
              "AWS/Lambda", "Invocations", { stat = "Sum", label = name }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "All Lambda Functions - Invocations"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 36
        width  = 12
        height = 6
        properties = {
          metrics = [
            for name, arn in var.lambda_function_names : [
              "AWS/Lambda", "Errors", { stat = "Sum", label = name }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "All Lambda Functions - Errors"
          period  = 300
        }
      },

      # ========================================
      # SECTION 7: Kafka Consumer Logs
      # ========================================
      {
        type   = "text"
        x      = 0
        y      = 42
        width  = 24
        height = 1
        properties = {
          markdown = "## 📜 Kafka Consumer Logs (Recent Messages)"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 43
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
          title   = "Recent Kafka Messages Consumed"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 49
        width  = 24
        height = 6
        properties = {
          query   = <<-EOT
            SOURCE '/aws/lambda/${var.environment}-${var.project_name}-kafka_consumer'
            | fields @timestamp, @message
            | filter @message like /ERROR/ or @message like /Exception/
            | sort @timestamp desc
            | limit 20
          EOT
          region  = data.aws_region.current.name
          title   = "Kafka Consumer - Errors & Exceptions"
        }
      }
    ]
  })
}

data "aws_region" "current" {}