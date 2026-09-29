# 🚀 Guide de Bootstrap - Infrastructure MCP

Ce guide vous explique comment déployer l'infrastructure de base AWS pour le projet MCP en utilisant Terraform.

## 📋 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Prérequis](#prérequis)
3. [Étape 1 : Bootstrap (Infrastructure de base)](#étape-1--bootstrap)
4. [Étape 2 : Infrastructure principale](#étape-2--infrastructure-principale)
5. [Étape 3 : GitHub Actions](#étape-3--github-actions)
6. [Dépannage](#dépannage)

---

## 🎯 Vue d'ensemble

Le déploiement se fait en **2 phases** :

```
Phase 1: Bootstrap (ce guide)
├── Créer les buckets S3 pour Terraform state
├── Créer les tables DynamoDB pour state locking
├── Créer le bucket S3 pour les JARs Lambda
└── Créer le rôle IAM pour GitHub Actions

Phase 2: Infrastructure principale
├── VPC, Subnets, Security Groups
├── Lambda Functions
├── Step Functions
├── API Gateway
├── DynamoDB tables (données)
└── MSK, SQS, CloudWatch, etc.
```

---

## ✅ Prérequis

### 1. Outils nécessaires

```bash
# Vérifier AWS CLI
aws --version
# Requis: aws-cli/2.x.x ou supérieur

# Vérifier Terraform
terraform --version
# Requis: Terraform v1.9.0 ou supérieur

# Si absent, installer:
# macOS
brew install awscli terraform

# Ou télécharger depuis:
# https://aws.amazon.com/cli/
# https://www.terraform.io/downloads
```

### 2. Compte AWS

- ✅ Compte AWS actif
- ✅ Utilisateur IAM avec permissions AdministratorAccess
- ✅ Access Key ID et Secret Access Key

### 3. Configurer AWS CLI

```bash
aws configure

# Réponses:
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtn...
Default region name [None]: ca-central-1
Default output format [None]: json
```

**Vérifier la configuration:**

```bash
aws sts get-caller-identity

# Output attendu:
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/votre-utilisateur"
}
```

---

## 🔧 Étape 1 : Bootstrap

### 1.1 Modifier la configuration

```bash
cd bootstrap

# Ouvrir terraform.tfvars
vim terraform.tfvars  # ou code terraform.tfvars

# ⚠️ IMPORTANT: Modifier cette ligne avec votre repo GitHub
github_repo = "votre-org/mcp-infrastructure"
# Exemple: "banque-nationale/mcp-infrastructure"
```

### 1.2 Initialiser Terraform

```bash
terraform init

# Output attendu:
# Initializing the backend...
# Initializing provider plugins...
# - Finding hashicorp/aws versions matching "~> 5.0"...
# - Installing hashicorp/aws v5.x.x...
# Terraform has been successfully initialized!
```

### 1.3 Valider la configuration

```bash
terraform validate

# Output attendu:
# Success! The configuration is valid.
```

### 1.4 Planifier le déploiement

```bash
terraform plan

# Output attendu (extrait):
# Terraform will perform the following actions:
#
#   # aws_s3_bucket.terraform_state_dev will be created
#   + resource "aws_s3_bucket" "terraform_state_dev" {
#       + bucket = "mcp-terraform-state-dev"
#       ...
#   }
#
#   # aws_dynamodb_table.terraform_lock_dev will be created
#   ...
#
# Plan: 15 to add, 0 to change, 0 to destroy.
```

### 1.5 Appliquer le déploiement

```bash
terraform apply

# Terraform demande confirmation:
# Do you want to perform these actions?
#   Enter a value: yes  ← Tapez "yes"

# Déploiement en cours... (2-3 minutes)
#
# Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
#
# Outputs:
#
# terraform_state_bucket_dev = "mcp-terraform-state-dev"
# terraform_state_bucket_prod = "mcp-terraform-state-prod"
# lambda_artifacts_bucket_name = "bnc-mcp-lambda-artifacts"
# dynamodb_lock_table_dev = "mcp-terraform-lock-dev"
# dynamodb_lock_table_prod = "mcp-terraform-lock-prod"
# github_actions_role_arn = "arn:aws:iam::123456789:role/mcp-github-actions-role"
# next_steps = "..."
```

### 1.6 Vérifier les ressources créées

```bash
# Vérifier les buckets S3
aws s3 ls | grep mcp

# Output:
# 2024-01-15 14:30:00 bnc-mcp-lambda-artifacts
# 2024-01-15 14:30:00 mcp-terraform-state-dev
# 2024-01-15 14:30:00 mcp-terraform-state-prod

# Vérifier les tables DynamoDB
aws dynamodb list-tables | grep terraform-lock

# Output:
# "mcp-terraform-lock-dev",
# "mcp-terraform-lock-prod"

# Vérifier le rôle IAM
aws iam get-role --role-name mcp-github-actions-role

# Devrait retourner les détails du rôle
```

---

## 🏗️ Étape 2 : Infrastructure principale

### 2.1 Le backend est déjà configuré

Le fichier `environments/dev/backend.tf` est déjà configuré pour utiliser les ressources créées par le bootstrap :

```hcl
backend "s3" {
  bucket         = "mcp-terraform-state-dev"      # ← Créé par bootstrap
  key            = "infrastructure/terraform.tfstate"
  region         = "ca-central-1"
  encrypt        = true
  dynamodb_table = "mcp-terraform-lock-dev"        # ← Créé par bootstrap
}
```

### 2.2 Déployer l'infrastructure DEV

```bash
cd ../environments/dev

# Initialiser (connecte au backend S3)
terraform init

# Output:
# Initializing the backend...
# Successfully configured the backend "s3"!

# Planifier
terraform plan

# Appliquer
terraform apply
```

---

## 🐙 Étape 3 : GitHub Actions

### 3.1 Récupérer le Role ARN

```bash
cd ../../bootstrap
terraform output github_actions_role_arn

# Output:
# "arn:aws:iam::123456789012:role/mcp-github-actions-role"
```

### 3.2 Mettre à jour le workflow GitHub Actions

Modifier `.github/workflows/terraform-deploy.yml` :

```yaml
# AVANT (avec credentials statiques - à supprimer)
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION }}

# APRÈS (avec OIDC - plus sécurisé)
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/mcp-github-actions-role
    role-session-name: GitHubActions-Terraform-${{ github.run_id }}
    aws-region: ca-central-1
```

### 3.3 Configurer GitHub Repository

**Permissions nécessaires:**

1. Repository → Settings → Actions → General
2. Workflow permissions → ✅ Read and write permissions

**Secrets (optionnel si OIDC utilisé):**

Vous pouvez maintenant **supprimer** ces secrets si vous utilisez OIDC :
- ❌ AWS_ACCESS_KEY_ID
- ❌ AWS_SECRET_ACCESS_KEY

Gardez seulement :
- ✅ DEV_IBM_MQ_HOST
- ✅ DEV_IBM_MQ_PASSWORD
- ✅ DEV_MDMAE_URL
- ✅ etc.

---

## 🔍 Dépannage

### Erreur : "Bucket already exists"

```
Error: creating Amazon S3 Bucket (mcp-terraform-state-dev): BucketAlreadyOwnedByYou
```

**Solution :** Le bucket existe déjà (peut-être créé manuellement). Options :

1. **Importer le bucket existant:**
   ```bash
   terraform import aws_s3_bucket.terraform_state_dev mcp-terraform-state-dev
   terraform import aws_s3_bucket.terraform_state_prod mcp-terraform-state-prod
   ```

2. **Ou renommer dans terraform.tfvars:**
   ```hcl
   terraform_state_bucket_name_dev = "mcp-terraform-state-dev-v2"
   ```

### Erreur : "Access Denied"

```
Error: error configuring S3 Backend: AccessDenied
```

**Solution :** Vérifiez vos permissions AWS :

```bash
aws iam get-user
aws iam list-attached-user-policies --user-name votre-utilisateur
```

Assurez-vous d'avoir `AdministratorAccess` ou les permissions nécessaires.

### Erreur : "Region mismatch"

```
Error: Error acquiring the state lock
```

**Solution :** Vérifiez que la région est cohérente partout :

```bash
# Dans terraform.tfvars
aws_region = "ca-central-1"

# Dans AWS CLI
aws configure get region
# Doit retourner: ca-central-1
```

---

## 📊 Architecture des ressources Bootstrap

```
Bootstrap (déployé UNE FOIS)
│
├── S3 Buckets
│   ├── mcp-terraform-state-dev      (State Terraform DEV)
│   ├── mcp-terraform-state-prod     (State Terraform PROD)
│   └── bnc-mcp-lambda-artifacts     (JARs Lambda)
│
├── DynamoDB Tables
│   ├── mcp-terraform-lock-dev       (Locking DEV)
│   └── mcp-terraform-lock-prod      (Locking PROD)
│
└── IAM (GitHub Actions)
    ├── OIDC Provider                (GitHub Actions)
    └── Role: mcp-github-actions-role
```

---

## 📝 Checklist complète

### Bootstrap
- [ ] AWS CLI configuré (`aws configure`)
- [ ] Terraform installé (`terraform --version`)
- [ ] `bootstrap/terraform.tfvars` modifié (github_repo)
- [ ] `terraform init` exécuté
- [ ] `terraform apply` réussi
- [ ] Ressources vérifiées dans AWS Console
- [ ] Role ARN récupéré

### Infrastructure principale
- [ ] `environments/dev/backend.tf` vérifié
- [ ] `cd environments/dev && terraform init`
- [ ] `terraform plan` exécuté
- [ ] `terraform apply` réussi

### GitHub Actions
- [ ] Workflow modifié avec role-to-assume
- [ ] Repository permissions configurées
- [ ] Secrets nettoyés (AWS_ACCESS_KEY_ID supprimé)
- [ ] Test du workflow réussi

---

## 🚀 Commandes de référence rapide

```bash
# Bootstrap (une fois)
cd bootstrap
terraform init
terraform apply

# Infrastructure DEV
cd ../environments/dev
terraform init
terraform apply

# Infrastructure PROD
cd ../environments/prod
terraform init
terraform apply

# Voir les outputs
terraform output

# Détruire (⚠️ DANGER)
terraform destroy
```

---

## 📞 Support

- Documentation Terraform : https://www.terraform.io/docs
- Documentation AWS Provider : https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- GitHub Actions OIDC : https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services

---

**✅ Vous êtes maintenant prêt à déployer l'infrastructure MCP sur AWS avec Terraform !**