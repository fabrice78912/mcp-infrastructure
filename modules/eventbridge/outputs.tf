output "rule_arns" {
  description = "Map of EventBridge rule ARNs"
  value       = { for k, v in aws_cloudwatch_event_rule.rules : k => v.arn }
}

output "rule_names" {
  description = "Map of EventBridge rule names"
  value       = { for k, v in aws_cloudwatch_event_rule.rules : k => v.name }
}