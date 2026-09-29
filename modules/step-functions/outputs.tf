output "state_machine_arns" {
  description = "Map of Step Functions state machine ARNs"
  value       = { for k, v in aws_sfn_state_machine.state_machines : k => v.arn }
}

output "state_machine_names" {
  description = "Map of Step Functions state machine names"
  value       = { for k, v in aws_sfn_state_machine.state_machines : k => v.name }
}

output "log_group_names" {
  description = "Map of CloudWatch log group names"
  value       = { for k, v in aws_cloudwatch_log_group.sfn_logs : k => v.name }
}