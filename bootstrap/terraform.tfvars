# Configuration Bootstrap
# ⚠️ Modifiez ces valeurs selon vos besoins

aws_region   = "ca-central-1"
project_name = "mcp"

# Noms des ressources (correspondent à ceux utilisés dans environments/*/backend.tf)
terraform_state_bucket_name_dev  = "mcp-terraform-state-dev-180111006463"
terraform_state_bucket_name_prod = "mcp-terraform-state-prod"
lambda_artifacts_bucket_name     = "bnc-mcp-lambda-artifacts"
dynamodb_lock_table_name_dev     = "mcp-terraform-lock-dev"
dynamodb_lock_table_name_prod    = "mcp-terraform-lock-prod"

# IAM User (false = utilise GitHub Actions OIDC à la place - recommandé)
create_iam_user = false
iam_user_name   = "terraform-deployer"

# ⚠️ IMPORTANT: Remplacez par votre organisation/repo GitHub
github_repo = "fabrice78912/mcp-infrastructure"