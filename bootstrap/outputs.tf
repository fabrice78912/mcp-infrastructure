output "terraform_state_bucket_dev" {
  description = "S3 bucket name for Terraform state (dev)"
  value       = aws_s3_bucket.terraform_state_dev.id
}

output "terraform_state_bucket_prod" {
  description = "S3 bucket name for Terraform state (prod)"
  value       = aws_s3_bucket.terraform_state_prod.id
}

output "lambda_artifacts_bucket_name" {
  description = "S3 bucket name for Lambda artifacts"
  value       = aws_s3_bucket.lambda_artifacts.id
}

output "dynamodb_lock_table_dev" {
  description = "DynamoDB table name for state locking (dev)"
  value       = aws_dynamodb_table.terraform_lock_dev.id
}

output "dynamodb_lock_table_prod" {
  description = "DynamoDB table name for state locking (prod)"
  value       = aws_dynamodb_table.terraform_lock_prod.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "next_steps" {
  description = "Instructions pour les prochaines étapes"
  value = <<-EOT

  ✅ Bootstrap terminé avec succès !

  📦 Ressources créées:

  DEV:
    - S3 Bucket State: ${aws_s3_bucket.terraform_state_dev.id}
    - DynamoDB Lock:   ${aws_dynamodb_table.terraform_lock_dev.id}

  PROD:
    - S3 Bucket State: ${aws_s3_bucket.terraform_state_prod.id}
    - DynamoDB Lock:   ${aws_dynamodb_table.terraform_lock_prod.id}

  SHARED:
    - Lambda Artifacts: ${aws_s3_bucket.lambda_artifacts.id}
    - GitHub Role ARN:  ${aws_iam_role.github_actions.arn}

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🔄 Prochaines étapes :

  1. Le backend S3 est déjà configuré dans environments/dev/backend.tf ✅

  2. Pour GitHub Actions, modifiez .github/workflows/terraform-deploy.yml:

     - name: Configure AWS credentials
       uses: aws-actions/configure-aws-credentials@v4
       with:
         role-to-assume: ${aws_iam_role.github_actions.arn}
         role-session-name: GitHubActions-Terraform
         aws-region: ca-central-1

  3. Mettre à jour le github_repo dans bootstrap/terraform.tfvars

  4. Déployer l'infrastructure principale:
     cd environments/dev
     terraform init
     terraform plan
     terraform apply

  EOT
}