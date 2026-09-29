output "cluster_arn" {
  description = "ARN of the MSK cluster"
  value       = aws_msk_serverless_cluster.main.arn
}

output "bootstrap_brokers" {
  description = "Bootstrap brokers for MSK cluster (IAM auth)"
  value       = aws_msk_serverless_cluster.main.bootstrap_brokers_sasl_iam
}

output "cluster_name" {
  description = "Name of the MSK cluster"
  value       = aws_msk_serverless_cluster.main.cluster_name
}