output "sns_topic_arn" {
  description = "ARN of SNS topic for alarms"
  value       = var.enable_alarms && var.alarm_email != "" ? aws_sns_topic.alarms[0].arn : null
}

output "dashboard_name" {
  description = "Name of CloudWatch dashboard"
  value       = var.enable_alarms ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "alarm_names" {
  description = "Map of CloudWatch alarm names"
  value = merge(
    { for k, v in aws_cloudwatch_metric_alarm.lambda_errors : "${k}-errors" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.lambda_duration : "${k}-duration" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : "${k}-throttles" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.stepfunctions_failed : "${k}-failed" => v.alarm_name }
  )
}